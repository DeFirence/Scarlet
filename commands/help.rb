# Help documentation
# help - Displays all of the help commands that Scarlet knows.
# help <query> - Displays all help commands that match <query>.

Scarlet.hear /help\s*(.*)?$/i, :dev do
  query = params[1].blank? ? nil : params[1] 
  Scarlet.get_help(query).each { |line|
    notice sender.nick, line
  }
end