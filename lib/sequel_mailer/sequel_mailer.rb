module Sequel
  module Mailer
    ##
    # Adds +mail+ to the Email table.  Only the first From address for +mail+ is
    # used.
    def sequel
      @mail.to.each do |destination|
        r = Email.create({
          :mail => @mail.to_s, 
          :to_address => destination,
          :from_address => @mail.from.first, 
          :created_on => Time.now
        })
      end
    end
  end
end

module Merb
  class Mailer
    # extends Merb::Mailer with the #sequel method
    include Sequel::Mailer
  end
end  

# module Sequel
#   class Mailer < Merb::Mailer
#     # @@email_class = Merb::Mailer.config[:sequel_mailer_class] || Email rescue
# 
#     
#   end

#  class MailController < Merb::MailController
#    self._mailer_klass = Sequel::Mailer
#  end
#end

