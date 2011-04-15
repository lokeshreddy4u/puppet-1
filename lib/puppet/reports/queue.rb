require 'puppet'
require 'puppet/util/queue'

Puppet::Reports.register_report(:queue) do
    def process
        client = Puppet::Util::Queue.queue_type_to_class(Puppet[:queue_type]).new
        destination = "puppet.reports"
        client.send_message(destination, self.to_yaml)
    end
end
