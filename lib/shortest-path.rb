# -*- coding: utf-8 -*-
require 'rubygems'

require 'dijkstraruby'

class ShortestPath
  attr_accessor :graph

  def initialize
    @graph = nil
  end

  def calc_shortest_path(topology)
    link_switches = []
    topology.links.each do |each|
      link_switches += [[each.dpid_a, each.dpid_b, 1]] unless each.is_connected_host
    end
    @graph = Dijkstraruby::Graph.new(link_switches)
    puts "calc!"
  end
  
  def get_shortest_path(src, dest)
    links_on_path = []
    links_result = []
    result = @graph.shortest_path(src, dest)
    i = 0
    while i < result.size - 1
      links_on_path += [[result[0][i], result[0][i+1]]]
      i += 1
    end
    links_on_path.each do |each|
      topology.links.each do |each2|
        if (each2.dpid_a == each[0]) && (each2.dpid_b == each[1])
          links_result += [[each2.dpid_a, each.port_a]]
          break
        end
      end
    end
    links_result
  end
  
end

### Local variables:
### mode: Ruby
### coding: utf-8-unix
### indent-tabs-mode: nil
### End:
