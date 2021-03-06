# when does next <show> episode air? - Searches for the next air date of <show>.
Scarlet.hear (/when does next (.+?)(?: episode)? air\??/), :registered do
  http = EventMachine::HttpRequest.new("http://www.tv.com/shows/#{params[1].parameterize}").get
  http.callback {
    info = http.response.match(/(?:<h1 itemprop="name">\s*(?<show_name>.+?)\s*<\/h1>).+(?:<li>\s*\n\s*<label>Status:<\/label>\s*\n\s*(?<status>.+?)\s*\n\s*<\/li>)(?:.+<div class="next_episode">.+<p class="highlight_date\s*">.+<span>\s*(?<date>.+?)\s*<\/span>.+class="highlight_name">\s*(?<name>.+?)\s*<\/a>.+class="highlight_season">\s*(?<season>.+?)\s*<\/p>)?/m)
    if info
      if info[:date]
        num = info[:season].match(/Season (\d+) : Episode (\d+)/)
        air = info[:date].match(/Airs on 2012/)
        date = DateTime.strptime(info[:date], "Airs on %m/%d/%Y").to_time
        reply "#{info[:show_name]} S#{"%02d" % num[1].to_i}E#{"%02d" % num[2].to_i} - #{info[:name]} airs on #{date.strftime("%A, #{date.day.ordinalize} %B %Y")}."
      elsif info[:status] == "Ended"
        reply "The series has ended."
      else
        reply "Next air date is unknown."
      end
    else
      reply "Series \"#{params[1]}\" not found."
    end
  }
end