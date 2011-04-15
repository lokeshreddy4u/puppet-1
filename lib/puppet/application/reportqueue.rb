require 'puppet'
require 'puppet/application'
require 'puppet/util/queue'

class Puppet::Application::Reportqueue < Puppet::Application
  should_parse_config
  run_mode :master

  attr_accessor :daemon

  def preinit
    require 'puppet/daemon'
    @daemon = Puppet::Daemon.new
    @daemon.argv = ARGV.dup
    Puppet::Util::Log.newdestination(:console)

    # Do an initial trap, so that cancels don't get a stack trace.

    # This exits with exit code 1
    trap(:INT) do
      $stderr.puts "Caught SIGINT; shutting down"
      exit(1)
    end

    # This is a normal shutdown, so code 0
    trap(:TERM) do
      $stderr.puts "Caught SIGTERM; shutting down"
      exit(0)
    end

    {
      :verbose => false,
      :debug => false
    }.each do |opt,val|
      options[opt] = val
    end
  end

  option("--debug","-d")
  option("--verbose","-v")

  def main
    Puppet.notice "Starting reportsqueue #{Puppet.version}"

    client = Puppet::Util::Queue.queue_type_to_class(Puppet[:queue_type]).new

    client.subscribe("puppet.reports") do |msg|
        begin
            report = YAML.load(msg)
            Puppet.debug("Got a report: #{report}")
            process(report)
          rescue => detail
            Puppet.err "Could not process report: {detail}"
            puts detail.backtrace if Puppet[:trace]
          end
    end

    Thread.list.each { |thread| thread.join }
  end

  def process(report)
      return if Puppet[:reports] == "none"

      # Taken from network/handler/report.rb
      reports.each do |name|
        if mod = Puppet::Reports.report(name)
          # We have to use a dup because we're including a module in the
          # report.
          newrep = report.dup
          begin
            newrep.extend(mod)
            newrep.process
          rescue => detail
            puts detail.backtrace if Puppet[:trace]
            Puppet.err "Report #{name} failed: #{detail}"
          end
        else
          Puppet.warning "No report named '#{name}'"
        end
      end
  end

  # Handle the parsing of the reports attribute.
  def reports
    # LAK:NOTE See http://snurl.com/21zf8  [groups_google_com]
    x = Puppet[:reports].gsub(/(^\s+)|(\s+$)/, '').split(/\s*,\s*/)
  end

  # Handle the logging settings.
  def setup_logs
    if options[:debug] or options[:verbose]
      Puppet::Util::Log.newdestination(:console)
      if options[:debug]
        Puppet::Util::Log.level = :debug
      else
        Puppet::Util::Log.level = :info
      end
    end
  end

  def setup
    unless Puppet.features.stomp?
      raise ArgumentError, "Could not load the 'stomp' library, which must be present for queueing to work.  You must install the required library."
    end

    setup_logs

    exit(Puppet.settings.print_configs ? 0 : 1) if Puppet.settings.print_configs?

    daemon.daemonize if Puppet[:daemonize]
  end
end
