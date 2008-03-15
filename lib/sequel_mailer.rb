# make sure we're running inside Merb
if defined?(Merb::Plugins)

  # Merb gives you a Merb::Plugins.config hash...feel free to put your stuff in your piece of it
  Merb::Plugins.config[:sequel_mailer] = {
  }
  
  require "merb-mailer"
  require "merb_sequel"
  require "sequel"
  require "sequel_mailer/sequel_mailer"
end