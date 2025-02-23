# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require 'openc3/utilities/store'
require 'openc3/models/target_model'

module OpenC3
  class CvtModel
    VALUE_TYPES = [:RAW, :CONVERTED, :FORMATTED, :WITH_UNITS]
    def self.build_json_from_packet(packet)
      packet.decom
    end

    # Delete the current value table for a target
    def self.del(target_name:, packet_name:, scope: $openc3_scope)
      Store.hdel("#{scope}__tlm__#{target_name}", packet_name)
    end

    # Set the current value table for a target, packet
    def self.set(hash, target_name:, packet_name:, scope: $openc3_scope)
      Store.hset("#{scope}__tlm__#{target_name}", packet_name, JSON.generate(hash.as_json(:allow_nan => true)))
    end

    # Set an item in the current value table
    def self.set_item(target_name, packet_name, item_name, value, type:, scope: $openc3_scope)
      hash = JSON.parse(Store.hget("#{scope}__tlm__#{target_name}", packet_name), :allow_nan => true, :create_additions => true)
      case type
      when :WITH_UNITS
        hash["#{item_name}__U"] = value.to_s # WITH_UNITS should always be a string
      when :FORMATTED
        hash["#{item_name}__F"] = value.to_s # FORMATTED should always be a string
      when :CONVERTED
        hash["#{item_name}__C"] = value
      when :RAW
        hash[item_name] = value
      when :ALL
        hash["#{item_name}__U"] = value.to_s # WITH_UNITS should always be a string
        hash["#{item_name}__F"] = value.to_s # FORMATTED should always be a string
        hash["#{item_name}__C"] = value
        hash[item_name] = value
      else
        raise "Unknown type '#{type}' for #{target_name} #{packet_name} #{item_name}"
      end
      Store.hset("#{scope}__tlm__#{target_name}", packet_name, JSON.generate(hash.as_json(:allow_nan => true)))
    end

    # Get an item from the current value table
    def self.get_item(target_name, packet_name, item_name, type:, scope: $openc3_scope)
      override_key = item_name
      types = []
      case type
      when :WITH_UNITS
        types = ["#{item_name}__U", "#{item_name}__F", "#{item_name}__C", item_name]
        override_key = "#{item_name}__U"
      when :FORMATTED
        types = ["#{item_name}__F", "#{item_name}__C", item_name]
        override_key = "#{item_name}__F"
      when :CONVERTED
        types = ["#{item_name}__C", item_name]
        override_key = "#{item_name}__C"
      when :RAW
        types = [item_name]
      else
        raise "Unknown type '#{type}' for #{target_name} #{packet_name} #{item_name}"
      end
      overrides = Store.hget("#{scope}__override__#{target_name}", packet_name)
      if overrides
        result = JSON.parse(overrides, :allow_nan => true, :create_additions => true)[override_key]
        return result if result
      end
      hash = JSON.parse(Store.hget("#{scope}__tlm__#{target_name}", packet_name), :allow_nan => true, :create_additions => true)
      hash.values_at(*types).each do |result|
        if result
          if type == :FORMATTED or type == :WITH_UNITS
            return result.to_s
          end
          return result
        end
      end
      return nil
    end

    # Return all item values and limit state from the CVT
    #
    # @param items [Array<String>] Items to return. Must be formatted as TGT__PKT__ITEM__TYPE
    # @param stale_time [Integer] Time in seconds from Time.now that value will be marked stale
    # @return [Array] Array of values
    def self.get_tlm_values(items, stale_time: 30, scope: $openc3_scope)
      now = Time.now.sys.to_f
      results = []
      lookups = []
      packet_lookup = {}
      overrides = {}
      # First generate a lookup hash of all the items represented so we can query the CVT
      items.each { |item| _parse_item(lookups, overrides, item, scope: scope) }

      lookups.each do |target_packet_key, target_name, packet_name, value_keys|
        unless packet_lookup[target_packet_key]
          packet = Store.hget("#{scope}__tlm__#{target_name}", packet_name)
          raise "Packet '#{target_name} #{packet_name}' does not exist" unless packet
          packet_lookup[target_packet_key] = JSON.parse(packet, :allow_nan => true, :create_additions => true)
        end
        hash = packet_lookup[target_packet_key]
        item_result = []
        if value_keys.is_a?(Hash) # Set in _parse_item to indicate override
          item_result[0] = value_keys['value']
        else
          value_keys.each do |key|
            item_result[0] = hash[key]
            break if item_result[0] # We want the first value
          end
          # If we were able to find a value, try to get the limits state
          if item_result[0]
            if now - hash['RECEIVED_TIMESECONDS'] > stale_time
              item_result[1] = :STALE
            else
              # The last key is simply the name (RAW) so we can append __L
              # If there is no limits then it returns nil which is acceptable
              item_result[1] = hash["#{value_keys[-1]}__L"]
              item_result[1] = item_result[1].intern if item_result[1] # Convert to symbol
            end
          else
            raise "Item '#{target_name} #{packet_name} #{value_keys[-1]}' does not exist" unless hash.key?(value_keys[-1])
          end
        end
        results << item_result
      end
      results
    end

    # Return all the overrides
    def self.overrides(scope: $openc3_scope)
      overrides = []
      TargetModel.names(scope: scope).each do |target_name|
        all = Store.hgetall("#{scope}__override__#{target_name}")
        next if all.nil? or all.empty?
        all.each do |packet_name, hash|
          items = JSON.parse(hash, :allow_nan => true, :create_additions => true)
          items.each do |key, value|
            item = {}
            item['target_name'] = target_name
            item['packet_name'] = packet_name
            item_name, value_type_key = key.split('__')
            item['item_name'] = item_name
            case value_type_key
            when 'U'
              item['value_type'] = 'WITH_UNITS'
            when 'F'
              item['value_type'] = 'FORMATTED'
            when 'C'
              item['value_type'] = 'CONVERTED'
            else
              item['value_type'] = 'RAW'
            end
            item['value'] = value
            overrides << item
          end
        end
      end
      overrides
    end

    # Override a current value table item such that it always returns the same value
    # for the given type
    def self.override(target_name, packet_name, item_name, value, type: :ALL, scope: $openc3_scope)
      hash = Store.hget("#{scope}__override__#{target_name}", packet_name)
      hash = JSON.parse(hash, :allow_nan => true, :create_additions => true) if hash
      hash ||= {} # In case the above didn't create anything
      case type
      when :ALL
        hash[item_name] = value
        hash["#{item_name}__C"] = value
        hash["#{item_name}__F"] = value.to_s
        hash["#{item_name}__U"] = value.to_s
      when :RAW
        hash[item_name] = value
      when :CONVERTED
        hash["#{item_name}__C"] = value
      when :FORMATTED
        hash["#{item_name}__F"] = value.to_s # Always a String
      when :WITH_UNITS
        hash["#{item_name}__U"] = value.to_s # Always a String
      else
        raise "Unknown type '#{type}' for #{target_name} #{packet_name} #{item_name}"
      end
      Store.hset("#{scope}__override__#{target_name}", packet_name, JSON.generate(hash.as_json(:allow_nan => true)))
    end

    # Normalize a current value table item such that it returns the actual value
    def self.normalize(target_name, packet_name, item_name, type: :ALL, scope: $openc3_scope)
      hash = Store.hget("#{scope}__override__#{target_name}", packet_name)
      hash = JSON.parse(hash, :allow_nan => true, :create_additions => true) if hash
      hash ||= {} # In case the above didn't create anything
      case type
      when :ALL
        hash.delete(item_name)
        hash.delete("#{item_name}__C")
        hash.delete("#{item_name}__F")
        hash.delete("#{item_name}__U")
      when :RAW
        hash.delete(item_name)
      when :CONVERTED
        hash.delete("#{item_name}__C")
      when :FORMATTED
        hash.delete("#{item_name}__F")
      when :WITH_UNITS
        hash.delete("#{item_name}__U")
      else
        raise "Unknown type '#{type}' for #{target_name} #{packet_name} #{item_name}"
      end
      if hash.empty?
        Store.hdel("#{scope}__override__#{target_name}", packet_name)
      else
        Store.hset("#{scope}__override__#{target_name}", packet_name, JSON.generate(hash.as_json(:allow_nan => true)))
      end
    end

    # PRIVATE METHODS

    # parse item and update lookups with packet_name and target_name and keys
    # return an ordered array of hash with keys
    def self._parse_item(lookups, overrides, item, scope:)
      target_name, packet_name, item_name, value_type = item.split('__')

      # We build lookup keys by including all the less formatted types to gracefully degrade lookups
      # This allows the user to specify WITH_UNITS and if there is no conversions it will simply return the RAW value
      case value_type
      when 'RAW'
        keys = [item_name]
      when 'CONVERTED'
        keys = ["#{item_name}__C", item_name]
      when 'FORMATTED'
        keys = ["#{item_name}__F", "#{item_name}__C", item_name]
      when 'WITH_UNITS'
        keys = ["#{item_name}__U", "#{item_name}__F", "#{item_name}__C", item_name]
      else
        raise "Unknown value type '#{value_type}'"
      end
      tgt_pkt_key = "#{target_name}__#{packet_name}"
      # Check the overrides cache for this target / packet
      unless overrides[tgt_pkt_key]
        override_data = Store.hget("#{scope}__override__#{target_name}", packet_name)
        if override_data
          overrides[tgt_pkt_key] = JSON.parse(override_data, :allow_nan => true, :create_additions => true)
        else
          overrides[tgt_pkt_key] = {}
        end
      end
      if overrides[tgt_pkt_key][keys[0]]
        # Set the result as a Hash to distingish it from the key array and from an overridden Array value
        keys = {'value' => overrides[tgt_pkt_key][keys[0]]}
      end
      lookups << [tgt_pkt_key, target_name, packet_name, keys]
    end
  end
end
