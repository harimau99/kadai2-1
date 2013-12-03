# -*- coding: utf-8 -*-
require 'forwardable'
require 'link'
require 'observer'
require 'trema-extensions/port'

#
# Topology information containing the list of known switches, ports,
# and links.
#
class Topology
  include Observable
  extend Forwardable

  attr_reader :links
  attr_reader :hosts

  def_delegator :@ports, :each_pair, :each_switch
  def_delegator :@hosts, :each, :each_host
  def_delegator :@links, :each, :each_link

  def initialize(command_line)
    @ports = Hash.new { [].freeze }
    @hosts = []
    @links = []
    add_observer command_line
  end

  def delete_switch(dpid)
    @ports[dpid].each do | each |
      delete_port each
    end
    @ports.delete dpid
  end

  def update_port(port)
    if port.down?
      delete_port port
    elsif port.up?
      add_port port
    end
  end

  def add_port(port)
    @ports[port.dpid] += [port]
  end

  def delete_port(port)
    @ports[port.dpid] -= [port]
    delete_link_by port
  end

  def add_link_by(dpid, packet_in)
    fail 'Not an LLDP packet!' unless packet_in.lldp?
    begin
      maybe_add_link Link.new(dpid, packet_in, false)
    rescue
      return
    end
    changed
    notify_observers self
  end

  def add_host(host_ip_addr)
    @hosts.push host_ip_addr unless @hosts.include?(host_ip_addr)
  end

  def add_host_to_link(dpid, packet_in)
    fail 'Not a IPv4 packet!' unless packet_in.ipv4?
    begin
      maybe_add_link Link.new(dpid, packet_in, true)
    rescue
      return
    end
    changed
    notify_observers self
  end

  def increment_link_weight_on_flow(dpid, port)
    @links.each do |each|
      if each.has?(dpid, port)
        puts "increment! dpid: " + dpid.to_s + " , port: " + port.to_s
        each.increment_weight
      end
    end
  end

  def decrement_link_weight_on_flow(dpid, port)
    @links.each do |each|
      if each.has?(dpid, port)
        each.decrement_weight
      end
    end
  end

  private

  def maybe_add_link(link)
    fail 'The link already exists.' if @links.include?(link)
    @links << link
  end

  def delete_link_by(port)
    @links.each do |each|
      if each.has?(port.dpid, port.number)
        changed
        @links -= [each]
        delete_host each.dpid_a
      end
    end
    notify_observers self
  end

  def delete_host(host_ip_addr)
    @hosts -= [host_ip_addr] if @hosts.include?(host_ip_addr)
  end
end

### Local variables:
### mode: Ruby
### coding: utf-8-unix
### indent-tabs-mode: nil
### End:
