require_relative "monkeypatches.rb"
module IrcBot::IrcCommands
  Commands = ::IrcBot.commands
  Todo = ::IrcBot::Todo
  Nick = ::IrcBot::Nick

  class Command
    class << self
      @@access_level = {:any => 0, :registered => 1, :vip => 2, :dev => 8, :owner => 9}
      @@permissions = {}
      @@help = {}
      @@arity = {}
      @@table = nil

      def commands_scope scope
        @@scope = scope
      end

      def generate_table t
        @@table = t
      end

      def access_levels l = {}
        @@permissions.merge! l
      end

      def help h = {}
        @@help.merge! h
      end

      def arities a = {}
        @@arity.merge! a
      end

      def on keyword, &block
        Commands[keyword] = { :arity => @@arity[keyword], :scope => @@scope, :help => @@help[keyword], :disable => false,
                              :table => @@table, :access_level => @@access_level[@@permissions[keyword]]  }
        cmd = Commands[keyword]

        cmd[:method] = Proc.new { |params, sender|
          # sets the target
          case cmd[:scope]
            when :return_to_sender
              target = sender[:target] == $config.irc_bot.nick ? sender[:nick] : sender[:target]
            when :channel
              target = $config.irc_bot.channel
            when :user
              target = sender[:nick]
          end
          # arity check
          if cmd[:arity] && !(cmd[:arity].is_a?(Range) ? cmd[:arity].member?(params.split(" ").length) : params.split(" ").length == cmd[:arity])
            if cmd[:help].is_a?(Array)
              cmd[:table] ? create_table(cmd[:help], 40).each { |line| msg target, line } : cmd[:help].each { |line| msg target, line }
            else
              msg target, cmd[:help]
            end
          else
            data = {:params => params, :sender => sender[:nick], :target => sender[:target]} #here we set the data we pass
            result = (self.instance_exec data, &block) #here we exec the function

            if result.is_a?(Array) #result processing
              cmd[:table] ? create_table(result, cmd[:table]).each { |line| msg target, line, true } : result.each { |line| msg target, line, true }
            elsif result.is_a?(String)
              msg target, result
            end
          end
        }
      end
    end
  end

  class RandomCommands < Command
    commands_scope :return_to_sender
    access_levels :colors => :dev
    arities :colors => 0

    on :colors do |data|
      test = []
      for i in 0..15
        test << "#{"%02d" % i}".align(10, :center).irc_color(0, i)
      end
      test
    end
  end

  class BotServ < Command
    commands_scope :return_to_sender
    access_levels :register => :any, :login => :any, :logut => :any, :alias => :registered
    arities :register => 0, :login => 0, :logout => 0

    on :register do |data|
      if @users[data[:sender]][:ns_login]
        if Nick.where(:nick => data[:sender]).empty?
          nick = Nick.new(:nick => data[:sender]).save!
          "Successfuly registered with the bot."
        else
          "ERROR: You are already registered!".irc_color(4,0)
        end
      else
        "You must login with NickServ first!"
      end
    end

    on :login do |data|
      if !Nick.where(:nick => data[:sender]).empty?
        if !@users[data[:sender]][:ns_login]
          check_nick_login data[:sender]
        else
          notice data[:sender], "#{data[:sender]}, you are already logged in!"
        end
      else
        notice data[:sender], "#{data[:sender]}, you do not have an account yet. Type !register."
      end
    end

    on :logout do |data|
      if @users[data[:sender]][:ns_login]
        @users[data[:sender]][:ns_login] = false
        notice data[:sender], "#{data[:sender]}, you are now logged out."
      end
    end

    on :alias do |data|
      # implement a command where we can 'alias' nicknames
    end
  end

  class HelpCommand < Command
    commands_scope :user
    access_levels :help => :any
    arities :help => 0..Float::INFINITY
    generate_table 70

    on :help do |data|
      if data[:params].blank?
        hlp = ["Help for [Bot]"]
        cmd = []
        devcmd =[]
        Commands.keys.each { |k| Commands[k.to_sym][:access_level] ? (Commands[k.to_sym][:access_level] > 1 ? devcmd << k.to_s : cmd << k.to_s) : cmd << k}
        ["Help for [Bot]", "Devel. commands available: #{devcmd.join(" ")}", "Commands available: #{cmd.join(" ")}"]
      else
        Commands[data[:params].to_sym][:help]
      end
    end
  end

  class BotCommands < Command
    commands_scope :return_to_sender
    access_levels :botban => :dev, :botunban => :dev, :botnick => :dev, :eval => :dev, :party => :registered, :toggle => :dev
    help :botban => "Usage: botban <user> [<user>...]", 
      :botunban => "Usage: botunban <user> [<user>...]", 
      :botnick => "Usage: botnick <nick>",
      :eval => "Usage: eval <ruby code>"
    arities :botban => 1..Float::INFINITY, :botunban => 1..Float::INFINITY, :botnick => 1, :eval => 1..Float::INFINITY, :party => 0, :toggle => 1

    on :botban do |data|
      nicks = data[:params].split(" ")
      nicks.each {|n| @banned << n }
      "#{nicks.join(", ")} #{nicks.length == 1 ? "is" : "are"} now banned from using the bot."
    end
    on :botunban do |data|
      nicks = data[:params].split(" ")
      nicks.each {|n| @banned.delete n }
      "Bot usage ban was revoked for #{nicks.join(", ")}."
    end
    on :botnick do |data|
      client_command :nick, :nick => data[:params].delete(' ')
    end
    on :eval do |data|
      if !Nick.where(:nick => data[:sender]).empty? && Nick.where(:nick => data[:sender]).first.privileges == 9
        params = data[:params]
      else
        safe = true
        names_list = ["a poopy-head", "a meanie", "a retard", "an idiot"]
        if data[:params].match(/(.*(Thread|Process|File|Kernel|system|Dir|IO|require|load|ENV|%x|\`|sleep|Modules|send|undef|\/0|INFINITY|loop|variable_set|\$|@|Nick.*privileges.*save!|disconnecting\s*\=\s*true).*)/) 
          params = "\"#{data[:sender]} is #{names_list[rand(4)-1]}.\"" 
        else 
          params = data[:params]
        end
        params.taint
      end

      begin
        t = Thread.new {
          Thread.current[:output] = "==> #{eval(params)}"
        }
        t.join(10)
        t[:output]
      rescue(Exception) => result
        "ERROR: #{result.message}".irc_color(4,0)
      end
    end
    on :party do |data|
      "PARTY! PARTY! YEEEEEEEA BOIIIIIII! ^.^ SO HAPPY, AWESOMEEEEE!"
    end

    on :toggle do |data|
      cmd = data[:params].strip.to_sym
      if cmd && cmd != :toggle
        if cmd != :eval
          if Commands.has_key?(cmd)
            Commands[cmd][:disable] = !Commands[cmd][:disable]
            "Command '#{data[:params]}' is now #{Commands[cmd][:disable] ? "disabled" : "enabled"}."
          else
            "Cannot toggle: Command '#{data[:params]}' does not exist."
          end
        else
          n = Nick.where(:nick => data[:sender])
          if n.count > 0 and n.first.privileges == 9 # quick fix
            Commands[:eval][:disable] = !Commands[:eval][:disable]
            "Command 'eval' is now #{Commands[:eval][:disable] ? "disabled" : "enabled"}."
          else
            "#{data[:sender]}, you do not have permission to use #{data[:params]}!"
          end
        end
      else
        "You cannot toggle :toggle!" if cmd == :toggle
      end
    end
  end

  class TodoCommands < Command
    commands_scope :return_to_sender
    access_levels :todo => :registered, :todel => :dev
    arities :todo => 1..Float::INFINITY, :todel => 1
    help :todo => "Usage: !todo (<list>|<count>|<show> <id>|<add> <text>)", :todel => "!todel <id>"
    generate_table 40

    on :todo do |data|
      command = data[:params].split[0...1].join(' ')
      sequence = data[:params].split(" ").drop(1).join(" ")

      case command.to_sym
        when :add
          Todo.new(:msg => sequence, :by => data[:sender]).save!
          "TODO was added."
        when :list
          c = Todo.all.count
          if c > 0
            todo_output = ["Last 10 entries:"]
            Todo.sort(:created_at.desc).limit(10).each_with_index { |t, i|
              break if i == 10 
              todo_output << "##{c-i}\t#{t.by}\t\t#{t.created_at.std_format}"
            }
            todo_output
          else
            "No entries found."
          end
        when :show
          id = sequence.split[0...1].join(' ').to_i
          t = Todo.sort(:created_at).all[id-1]
          if t
            [ "TODO ##{id}", "Date: #{t.created_at.std_format}", "Added by: #{t.by}", "Entry: #{t.msg}"]
          else
            "TODO ##{id} could not be found."
          end
        when :count
          "TODO count: #{Todo.all.count}"
        else
          "Invalid command."
      end
    end
    on :todel do |data|
      id = data[:params].strip.to_i - 1
      t = Todo.sort(:created_at).all[id].delete
      "TODO ##{data[:params]} was deleted."
    end
  end
end