# -*- coding: utf-8 -*-
$LOAD_PATH.unshift File.expand_path(File.join File.dirname(__FILE__), 'lib')

require 'rubygems'
require 'bundler/setup'

require 'command-line'
require 'topology'
require 'trema'
require 'trema-extensions/port'

#
# This controller collects network topology information using LLDP.
#
class TopologyController < Controller
  periodic_timer_event :flood_lldp_frames, 1

  FLOWHARDTIMEOUT = 300

  def start
    @fdb = {}
    @command_line = CommandLine.new
    @command_line.parse(ARGV.dup)
    @topology = Topology.new(@command_line)
  end

  def switch_ready(dpid)
    send_message dpid, FeaturesRequest.new
  end

  def features_reply(dpid, features_reply)
    features_reply.physical_ports.select(&:up?).each do |each|
      @topology.add_port each
    end
  end

  def switch_disconnected(dpid)
    @fdb.each_pair {|key, value| 
      if value.dpid == dpid
        @fdb.delete(key)
      end
    }
    @topology.delete_switch dpid
  end

  def port_status(dpid, port_status)
    updated_port = port_status.port
    return if updated_port.local?
    @topology.update_port updated_port
  end

  def packet_in(dpid, packet_in)
    if packet_in.ipv4?
      unless @topology.hosts.include?(packet_in.ipv4_saddr.to_s)
        @topology.add_host packet_in.ipv4_saddr.to_s
        @topology.add_host_to_link dpid, packet_in
      end
      # fdb に message の macsa と dpid, in_port を学習させる
      @fdb[ packet_in.macsa ] = { "dpid" => dpid, "in_port" => packet_in.in_port } unless @fdb.key?(packet_in.macsa)
      # message の macda からポート番号を fdb から引く
      dest_host = @fdb[ packet_in.macda ]
      if dest_host
        if dest_host["dpid"] == dpid
          flow_mod(dpid, packet_in, dest_host["in_port"], FLOWHARDTIMEOUT)
          packet_out(dpid, packet_in, dest_host["in_port"])
        else
          # dijkstra の結果から最短経路の情報を取得
          puts "process_dpid " + dpid.to_s
          puts "dst_dpid " + dest_host["dpid"].to_s
          links_result = @command_line.shortest_path.get_shortest_path(@topology, dpid, dest_host["dpid"])
          p links_result
          # 最短経路上のスイッチにフローを書込み
          if links_result.length > 1
            links_result.each do |each|
              puts "[dpid, port] = [#{each[0]}, #{each[1]}]"
              flow_mod(each[0], packet_in, each[1].to_i, FLOWHARDTIMEOUT)
            end
            packet_out(dpid, packet_in, links_result[0][1].to_i)
          end
        end 
      else
        # noop or flood
      end

    elsif packet_in.lldp?
      @topology.add_link_by dpid, packet_in
    end
  end

  private

  def flood_lldp_frames
    @topology.each_switch do |dpid, ports|
      send_lldp dpid, ports
    end
  end

  def send_lldp(dpid, ports)
    ports.each do |each|
      port_number = each.number
      send_packet_out(
        dpid,
        actions: SendOutPort.new(port_number),
        data: lldp_binary_string(dpid, port_number)
      )
    end
  end

  def lldp_binary_string(dpid, port_number)
    destination_mac = @command_line.destination_mac
    if destination_mac
      Pio::Lldp.new(dpid: dpid,
                    port_number: port_number,
                    destination_mac: destination_mac.value).to_binary
    else
      Pio::Lldp.new(dpid: dpid, port_number: port_number).to_binary
    end
  end

   def flow_mod(dpid, message, port, timeout)
    send_flow_mod_add(
      dpid,
      :hard_timeout => timeout,
      :match => Match.new(:dl_dst => message.macda.to_s),
      :actions => SendOutPort.new(port)
    )
  end

   def packet_out(dpid, message, port)
     send_packet_out(
       dpid,
       :packet_in => message,
       :actions => SendOutPort.new(port)
     )
   end
   
end

### Local variables:
### mode: Ruby
### coding: utf-8-unix
### indent-tabs-mode: nil
### End:
