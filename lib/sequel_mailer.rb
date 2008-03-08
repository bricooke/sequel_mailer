# make sure we're running inside Merb
if defined?(Merb::Plugins)

  # Merb gives you a Merb::Plugins.config hash...feel free to put your stuff in your piece of it
  Merb::Plugins.config[:sequel_mailer] = {
    :chickens => false
  }
  
  Merb::BootLoader.before_app_loads do
  end
  
  Merb::BootLoader.after_app_loads do
    require "merb-mailer"
    require "merb_sequel"
    require "sequel"
    
    module Sequel
      class Mailer < Merb::Mailer
        @@email_class = Merb::Mailer.config[:sequel_mailer_class] || Email rescue
  
        ##
        # Adds +mail+ to the Email table.  Only the first From address for +mail+ is
        # used.
        def sequel
          @mail.to.each do |destination|
            r = @@email_class.create({
              :mail => @mail.to_s, 
              :to_address => destination,
              :from_address => @mail.from.first, 
              :created_on => Time.now
            })
          end
        end
      end
    
      class MailController < Merb::MailController
        self._mailer_klass = Sequel::Mailer
      end
    end
  end
  
  Merb::Plugins.add_rakefiles "sequel_mailer/merbtasks"
end