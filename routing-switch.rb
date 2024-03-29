# -*- coding: utf-8 -*-
$LOAD_PATH.unshift File.expand_path(File.join File.dirname(__FILE__), 'lib')

require 'rubygems'
require 'bundler/setup'

require 'command-line'
require 'topology'
require 'trema'
require 'trema-extensions/port'

#
# Routing Switch using LLDP to collect network topology information.
#
class RoutingSwitch < Controller
  periodic_timer_event :flood_lldp_frames, 1

  MINCOOKIE = 0
  HARDTIMEOUTTOHOST = 60
  INITIALHARDTIMEOUT = 60
  DIFFHARDTIMEOUT = 1

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
    @fdb.each_pair do |key, value|
      @fdb.delete(key) if value['dpid'] == dpid
    end
    @topology.delete_switch dpid
  end

  def port_status(dpid, port_status)
    updated_port = port_status.port
    return if updated_port.local?
    @topology.update_port updated_port
  end

  def packet_in(dpid, packet_in)
    if packet_in.ipv4?
      add_host_by_packet_in dpid, packet_in
      learn_new_host_fdb dpid, packet_in
      dest_host = @fdb[packet_in.macda]
      set_flow_for_routing dpid, packet_in, dest_host if dest_host
    elsif packet_in.lldp?
      @topology.add_link_by dpid, packet_in
    end
  end

  def flow_removed(dpid, flow_removed)
    if flow_removed.cookie && (flow_removed.cookie.to_i > MINCOOKIE)
      cookie = flow_removed.cookie.to_i
      puts "flow_removed in dpid= #{dpid.to_s}, cookie= #{cookie.to_i}"
      @topology.decrement_link_weight_on_flow dpid, cookie
    end
  end

  private

  def learn_new_host_fdb(dpid, packet_in)
    unless @fdb.key?(packet_in.macsa)
      new_host = { 'dpid' => dpid, 'in_port' => packet_in.in_port }
      @fdb[packet_in.macsa] = new_host
    end
  end

  def add_host_by_packet_in(dpid, packet_in)
    unless @topology.hosts.include?(packet_in.ipv4_saddr.to_s)
      @topology.add_host packet_in.ipv4_saddr.to_s
      @topology.add_host_to_link dpid, packet_in
    end
  end

  def set_flow_for_routing(dpid, packet_in, dest_host)
    if dest_host['dpid'] == dpid
      flow_mod_to_host(dpid, packet_in, dest_host['in_port'], HARDTIMEOUTTOHOST)
      packet_out(dpid, packet_in, dest_host['in_port'])
    else
      sp = @command_line.shortest_path
      links_result = sp.get_shortest_path(@topology, dpid, dest_host['dpid'])
      if links_result.length > 0
        temp_timeout = INITIALHARDTIMEOUT
        links_result.each do |each|
          flow_mod(each[0], packet_in, each[1], temp_timeout)
          puts "add flow in dpid= #{each[0]}, port= #{each[1].to_i}"
          @topology.increment_link_weight_on_flow each[0], each[1]
          temp_timeout = temp_timeout + DIFFHARDTIMEOUT
        end
      end
    end
  end

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
      hard_timeout: timeout,
      match: Match.new(dl_src: message.macsa.to_s, dl_dst: message.macda.to_s),
      actions: SendOutPort.new(port.to_i),
      cookie: port.to_i
    )
  end

  def flow_mod_to_host(dpid, message, port, timeout)
    send_flow_mod_add(
      dpid,
      hard_timeout: timeout,
      match: Match.new(dl_dst: message.macda.to_s),
      actions: SendOutPort.new(port),
      cookie: MINCOOKIE
    )
  end

  def packet_out(dpid, message, port)
    send_packet_out(
      dpid,
      packet_in: message,
      actions: SendOutPort.new(port)
    )
  end
end

### Local variables:
### mode: Ruby
### coding: utf-8-unix
### indent-tabs-mode: nil
### End:
