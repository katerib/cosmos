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

require 'openc3/operators/operator'
require 'openc3/models/process_status_model'
require 'openc3/models/scope_model'
require 'openc3/utilities/logger'
require 'socket'

module OpenC3
  class ProcessManagerProcess < OperatorProcess
    attr_accessor :process_type
    attr_accessor :detail
    attr_accessor :expires_at
    attr_accessor :status
    attr_accessor :name

    def initialize(cmd_array, process_type, detail, expires_at, **kw_args)
      super(cmd_array, **kw_args)
      @process_type = process_type
      @detail = detail
      @expires_at = expires_at
      @status = nil
    end

    def start
      super()
      if @process
        @status = ProcessStatusModel.new(name: @name, process_type: @process_type, detail: @detail, state: "Running", scope: @scope)
        @status.create
      end
    end
  end

  # Spawns short lived processes and ensures they complete
  class ProcessManager
    MONITOR_CYCLE_SECONDS = 5
    CLEANUP_CYCLE_SECONDS = 600

    @@instance = nil

    def self.instance
      @@instance = ProcessManager.new unless @@instance
      return @@instance
    end

    def initialize
      @processes = []
      @monitor_thread = Thread.new do
        begin
          monitor()
        rescue => err
          Logger.error("ProcessManager unexpectedly died\n#{err.formatted}", scope: 'DEFAULT')
          raise "ProcessManager unexpectedly died\n#{err.formatted}"
        end
      end
    end

    def spawn(cmd_array, process_type, detail, expires_at, **kw_args)
      process = ProcessManagerProcess.new(cmd_array, process_type, detail, expires_at, **kw_args)
      process.start
      @processes << process
      return process
    end

    def monitor
      processes_to_delete = []
      cleanup_time = Time.now
      while true
        current_time = Time.now

        # Monitor Active Processes
        @processes.each do |process|
          # Check if the process is still alive
          if !process.alive?
            output = process.extract_output
            process.status.output = output
            if process.exit_code != 0
              process.status.state = "Crashed"
            elsif output.include?('"severity":"ERROR"') || output.include?('"severity":"WARN"')
              process.status.state = "Warning"
            else
              process.status.state = "Complete"
            end
            process.hard_stop
            processes_to_delete << process
          elsif process.expires_at < current_time
            process.status.state = "Expired"
            output = process.extract_output
            process.status.output = output
            process.hard_stop
            processes_to_delete << process
          end

          # Update Process Status
          process.status.update
        end
        processes_to_delete.each do |process|
          if process.status.state == "Complete"
            Logger.info("Process #{process.status.name}:#{process.process_type}:#{process.detail} completed with state #{process.status.state}", scope: process.scope)
          else
            Logger.error("Process #{process.status.name}:#{process.process_type}:#{process.detail} completed with state #{process.status.state}", scope: process.scope)
            Logger.error("Process Output:\n#{process.status.output}", scope: process.scope)
          end

          @processes.delete(process)
        end
        processes_to_delete.clear

        # Cleanup Old Process Status
        if (current_time - cleanup_time) > CLEANUP_CYCLE_SECONDS
          scopes = ScopeModel.names
          scopes.each do |scope|
            statuses = ProcessStatusModel.get_all_models(scope: scope)
            statuses.each do |status_name, status|
              if (current_time - Time.from_nsec_from_epoch(status.updated_at)) > CLEANUP_CYCLE_SECONDS
                status.destroy
              end
            end
          end
        end

        sleep(MONITOR_CYCLE_SECONDS)
      end
    end

  end
end
