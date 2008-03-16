require 'optparse'
require 'net/smtp'
require 'smtp_tls'
require 'rubygems'
require 'sequel'
require 'sequel_model'
require 'merb-core'
require 'merb-more'

class Object # :nodoc:
  unless respond_to? :path2class then
    def self.path2class(path)
      path.split(/::/).inject self do |k,n| k.const_get n end
    end
  end
end

##
# Hack in RSET

module Net # :nodoc:
class SMTP # :nodoc:

  unless instance_methods.include? 'reset' then
    ##
    # Resets the SMTP connection.

    def reset
      getok 'RSET'
    end
  end

end
end

##
# Sequel::Sendmail delivers email from the email table to the
# SMTP server configured in your application's config/init.rb.
# sequel_sendmail does not work with sendmail delivery.
#
# sequel_mailer can deliver to SMTP with TLS using smtp_tls.rb borrowed from Kyle
# Maxwell's action_mailer_optional_tls plugin.  Simply set the :tls option in
# Merb::Mailer.config to true to enable TLS.
#
# See sequel_sendmail -h for the full list of supported options.
#
# The interesting options are:
# * --daemon
# * --mailq
# * --create-migration
# * --create-model
# * --table-name

class Sequel::Sendmail

  ##
  # The version of Sequel::Sendmail you are running.

  VERSION = '0.0.2'

  ##
  # Maximum number of times authentication will be consecutively retried

  MAX_AUTH_FAILURES = 2

  ##
  # Email delivery attempts per run

  attr_accessor :batch_size

  ##
  # Seconds to delay between runs

  attr_accessor :delay

  ##
  # Maximum age of emails in seconds before they are removed from the queue.

  attr_accessor :max_age

  ##
  # Be verbose

  attr_accessor :verbose

  ##
  # Sequel class that holds emails

  attr_reader :email_class

  ##
  # True if only one delivery attempt will be made per call to run

  attr_reader :once

  ##
  # Times authentication has failed

  attr_accessor :failed_auth_count

  ##
  # Creates a new migration using +table_name+ and prints it on stdout.

  def self.create_migration(table_name)
    puts <<-EOF
class #{table_name.classify}Migration < Sequel::Migration
  def up
    create_table "#{table_name.tableize}" do
      primary_key :id
      varchar :from_address
      varchar :to_address
      integer :last_send_attempt, :default => 0
      text    :mail
      datetime :created_on
    end
  end

  def down
    execute "DROP TABLE #{table_name.tableize}"
  end

end
    EOF
  end

  ##
  # Creates a new model using +table_name+ and prints it on stdout.

  def self.create_model(table_name)
    puts <<-EOF
class #{table_name.classify} < Sequel::Model
end
    EOF
  end

  ##
  # Prints a list of unsent emails and the last delivery attempt, if any.
  #
  def self.mailq(table_name)
    klass = table_name.split('::').inject(Object) { |k,n| k.const_get n }
    emails = klass.all

    if emails.empty? then
      puts "Mail queue is empty"
      return
    end

    total_size = 0

    puts "-Queue ID- --Size-- ----Arrival Time---- -Sender/Recipient-------"
    emails.each do |email|
      size = email.mail.length
      total_size += size

      create_timestamp = email.created_on rescue
                         email.created_at rescue
                         Time.at(email.created_date) rescue # for Robot Co-op
                         nil

      created = if create_timestamp.nil? then
                  '             Unknown'
                else
                  create_timestamp.strftime '%a %b %d %H:%M:%S'
                end

      puts "%10d %8d %s  %s" % [email.id, size, created, email.from_address]
      if email.last_send_attempt > 0 then
        puts "Last send attempt: #{Time.at email.last_send_attempt}"
      end
      puts "                                         #{email.to_address}"
      puts
    end

    puts "-- #{total_size/1024} Kbytes in #{emails.length} Requests."
  end

  ##
  # Processes command line options in +args+

  def self.process_args(args)
    name = File.basename $0

    options = {}
    options[:Chdir] = '.'
    options[:Daemon] = false
    options[:Delay] = 60
    options[:MaxAge] = 86400 * 7
    options[:Once] = false
    options[:MerbEnv] = ENV['MERB_ENV'] || "development"
    options[:TableName] = 'Email'

    opts = OptionParser.new do |opts|
      opts.banner = "Usage: #{name} [options]"
      opts.separator ''

      opts.separator "#{name} scans the email table for new messages and sends them to the"
      opts.separator "website's configured SMTP host."
      opts.separator ''
      opts.separator "#{name} must be run from a Merb application's root."

      opts.separator ''
      opts.separator 'Sendmail options:'

      opts.on("-b", "--batch-size BATCH_SIZE",
              "Maximum number of emails to send per delay",
              "Default: Deliver all available emails", Integer) do |batch_size|
        options[:BatchSize] = batch_size
      end

      opts.on(      "--delay DELAY",
              "Delay between checks for new mail",
              "in the database",
              "Default: #{options[:Delay]}", Integer) do |delay|
        options[:Delay] = delay
      end

      opts.on(      "--max-age MAX_AGE",
              "Maxmimum age for an email. After this",
              "it will be removed from the queue.",
              "Set to 0 to disable queue cleanup.",
              "Default: #{options[:MaxAge]} seconds", Integer) do |max_age|
        options[:MaxAge] = max_age
      end

      opts.on("-o", "--once",
              "Only check for new mail and deliver once",
              "Default: #{options[:Once]}") do |once|
        options[:Once] = once
      end

      opts.on("-d", "--daemonize",
              "Run as a daemon process",
              "Default: #{options[:Daemon]}") do |daemon|
        options[:Daemon] = true
      end

      opts.on(      "--mailq",
              "Display a list of emails waiting to be sent") do |mailq|
        options[:MailQ] = true
      end

      opts.separator ''
      opts.separator 'Setup Options:'

      opts.on(      "--create-migration",
              "Prints a migration to add an Email table",
              "to stdout") do |create|
        options[:Migrate] = true
      end

      opts.on(      "--create-model",
              "Prints a model for an Email Sequel",
              "object to stdout") do |create|
        options[:Model] = true
      end

      opts.separator ''
      opts.separator 'Generic Options:'

      opts.on("-c", "--chdir PATH",
              "Use PATH for the application path",
              "Default: #{options[:Chdir]}") do |path|
        usage opts, "#{path} is not a directory" unless File.directory? path
        usage opts, "#{path} is not readable" unless File.readable? path
        options[:Chdir] = path
      end

      opts.on("-e", "--environment MERB_ENV",
              "Set the MERB_ENV constant",
              "Default: #{options[:MerbEnv]}") do |env|
        options[:MerbEnv] = env
      end

      opts.on("-t", "--table-name TABLE_NAME",
              "Name of table holding emails",
              "Used for both sendmail and",
              "migration creation",
              "Default: #{options[:TableName]}") do |name|
        options[:TableName] = name
      end

      opts.on("-v", "--[no-]verbose",
              "Be verbose",
              "Default: #{options[:Verbose]}") do |verbose|
        options[:Verbose] = verbose
      end

      opts.on("-h", "--help",
              "You're looking at it") do
        usage opts
      end

      opts.separator ''
    end

    opts.parse! args

    return options if options.include? :Migrate or options.include? :Model

    ENV['MERB_ENV'] = options[:MerbEnv]

    Dir.chdir options[:Chdir] do
      begin
        require 'config/init.rb'
      rescue LoadError
        usage opts, <<-EOF
#{name} must be run from a Merb application's root to deliver email.
#{Dir.pwd} does not appear to be a Merb application root.
          EOF
      end
    end

    return options
  end

  ##
  # Processes +args+ and runs as appropriate

  def self.run(args = ARGV)
    options = process_args args

    require "app" / "models" / "#{options[:TableName].underscore}.rb"
    
    # This connects us to the db, etc
    Merb.environment = options[:MerbEnv]
    Merb::Config.setup
    Merb.root = Merb::Config[:merb_root]
    Merb::BootLoader.run
    
    if options.include? :Migrate then
      create_migration options[:TableName]
      exit
    elsif options.include? :Model then
      create_model options[:TableName]
      exit
    elsif options.include? :MailQ then
      mailq options[:TableName]
      exit
    end

    if options[:Daemon] then
      require 'webrick/server'
      WEBrick::Daemon.start
    end

    new(options).run

  rescue SystemExit
    raise
  rescue SignalException
    exit
  rescue Exception => e
    $stderr.puts "Unhandled exception #{e.message}(#{e.class}):"
    $stderr.puts "\t#{e.backtrace.join "\n\t"}"
    exit 1
  end

  ##
  # Prints a usage message to $stderr using +opts+ and exits

  def self.usage(opts, message = nil)
    if message then
      $stderr.puts message
      $stderr.puts
    end

    $stderr.puts opts
    exit 1
  end

  ##
  # Creates a new Sequel::Sendmail.
  #
  # Valid options are:
  # <tt>:BatchSize</tt>:: Maximum number of emails to send per delay
  # <tt>:Delay</tt>:: Delay between deliver attempts
  # <tt>:TableName</tt>:: Table name that stores the emails
  # <tt>:Once</tt>:: Only attempt to deliver emails once when run is called
  # <tt>:Verbose</tt>:: Be verbose.

  def initialize(options = {})
    options[:Delay] ||= 60
    options[:TableName] ||= 'Email'
    options[:MaxAge] ||= 86400 * 7

    @batch_size = options[:BatchSize]
    @delay = options[:Delay]
    @email_class = Object.path2class options[:TableName]
    @once = options[:Once]
    @verbose = options[:Verbose]
    @max_age = options[:MaxAge]

    @failed_auth_count = 0
  end

  ##
  # Removes emails that have lived in the queue for too long.  If max_age is
  # set to 0, no emails will be removed.

  def cleanup
    return if @max_age == 0
    timeout = Time.now - @max_age
    conditions = ['last_send_attempt > 0 and created_on < ?', timeout]
    mail = @email_class.destroy_all conditions

    log "expired #{mail.length} emails from the queue"
  end

  ##
  # Delivers +emails+ to Merb::Mailer's SMTP server and destroys them.

  def deliver(emails)
    user = Merb::Mailer.config[:user] || Merb::Mailer.config[:user_name]
    Net::SMTP.start Merb::Mailer.config[:host], 
                    Merb::Mailer.config[:port],
                    Merb::Mailer.config[:domain], 
                    user,
                    Merb::Mailer.config[:password],
                    Merb::Mailer.config[:auth],
                    Merb::Mailer.config[:tls] do |smtp|
      @failed_auth_count = 0
      until emails.empty? do
        email = emails.shift
        begin
          res = smtp.send_message email.mail, email.from_address, email.to_address
          email.destroy
          log "sent email %011d from %s to %s: %p" %
                [email.id, email.from_address, email.to_address, res]
        rescue Net::SMTPFatalError => e
          log "5xx error sending email %d, removing from queue: %p(%s):\n\t%s" %
                [email.id, e.message, e.class, e.backtrace.join("\n\t")]
          email.destroy
          smtp.reset
        rescue Net::SMTPServerBusy => e
          log "server too busy, sleeping #{@delay} seconds"
          sleep delay
          return
        rescue Net::SMTPUnknownError, Net::SMTPSyntaxError, TimeoutError => e
          email.last_send_attempt = Time.now.to_i
          email.save rescue nil
          log "error sending email %d: %p(%s):\n\t%s" %
                [email.id, e.message, e.class, e.backtrace.join("\n\t")]
          smtp.reset
        end
      end
    end
  rescue Net::SMTPAuthenticationError => e
    @failed_auth_count += 1
    if @failed_auth_count >= MAX_AUTH_FAILURES then
      log "authentication error, giving up: #{e.message}"
      raise e
    else
      log "authentication error, retrying: #{e.message}"
    end
    sleep delay
  rescue Net::SMTPServerBusy, SystemCallError, OpenSSL::SSL::SSLError
    # ignore SMTPServerBusy/EPIPE/ECONNRESET from Net::SMTP.start's ensure
  end

  ##
  # Prepares ar_sendmail for exiting

  def do_exit
    log "caught signal, shutting down"
    exit
  end

  ##
  # Returns emails in email_class that haven't had a delivery attempt in the
  # last 300 seconds.

  def find_emails
    options = { :conditions => ['last_send_attempt < ?', Time.now.to_i - 300] }
    options[:limit] = batch_size unless batch_size.nil?
    mail = @email_class.find :all, options

    log "found #{mail.length} emails to send"
    mail
  end

  ##
  # Installs signal handlers to gracefully exit.

  def install_signal_handlers
    trap 'TERM' do do_exit end
    trap 'INT'  do do_exit end
  end

  ##
  # Logs +message+ if verbose

  def log(message)
    $stderr.puts message if @verbose
    ActionMailer::Base.logger.info "ar_sendmail: #{message}"
  end

  ##
  # Scans for emails and delivers them every delay seconds.  Only returns if
  # once is true.

  def run
    install_signal_handlers

    loop do
      now = Time.now
      begin
        cleanup        
        deliver find_emails
      end
      break if @once
      sleep @delay if now + @delay > Time.now
    end
  end
end

