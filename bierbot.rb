#!/usr/bin/env ruby
require 'rubygems'
gem 'hpricot', '>= 0.5'
gem 'twitter', '>= 1.1'

require 'hpricot'
require 'open-uri'
require 'twitter'
require 'yaml'

class Object
  def blank?
    if respond_to?(:empty?)
      empty? || nil?
    else
      nil?
    end
  end
end



target = "http://www.bierbrewery.com/index.html"

twitter_config_path = ".bier_bot_auth"
target_memory_path = ".bier_bot_history"

target_memory = ""
if File.exists?(target_memory_path)
  target_memory = File.read(target_memory_path)
end


if !File.exists?(twitter_config_path)
  raise "No twitter config file (#{twitter_config_path}) present - bierbot LOSING ITS SHIT"
end

twitter_config = YAML.load(File.read(twitter_config_path))

results = open(target).read rescue nil

if results
  results.gsub!(/<\/?(font|b|img|a|noscript)[^>]*>/im, " ") 
  results.gsub!(/&([a-z]|#[0-9])+;/im, " ")
  results.gsub!(/style\s*=\s*['"].+?['"]/im, "")
  results.gsub!(/<script[^>]*>.*?<\/script>/im, "")
  results.gsub!(/<!--\s*<\/?hs:[^>]*>\s*-->/im, "")
  results.gsub!(/\s{2,}/, " ")
end

up_and_coming = []
this_week = []

doc = Hpricot(results)

bier_candidates = doc.search("*").grep(Hpricot::Text)

up_and_coming_start = bier_candidates.select { |nd| nd.to_s =~ /Up((\s*'n )?coming)/i }.first
if up_and_coming_start 
  parent = up_and_coming_start.parent
  current = parent.next_sibling
  if current.inner_html =~ /b(ie|ee)rs:/i
    current = current.next_sibling
  end
  while current.inner_html.strip.blank?
    current = current.next_sibling
  end
  while !current.inner_html.strip.blank?
    bier = current.inner_html
    if bier =~ /-\s*[^\s]+/
      bier, desc = bier.split(/-/)
      current = current.next_sibling
    else
      desc = current.next_sibling.inner_html
      current = current.next_sibling.next_sibling
    end
    up_and_coming << [bier.gsub(/-\s+/, "").strip, desc.strip]
  end
end
up_and_coming = up_and_coming.sort_by { |pair| pair.first }

ordinals = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "nineth", "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth",
"sixteenth", "seventeenth", "eighteenth", "ninteteenth", "twentieth", "twenty-?first", "twenty-?second", "twenty-?third", "twenty-?fourth", "twenty-?fifth", "twenty-?sixth",
"twenty-?seventh", "twenty-?eighth", "twenty-?nineth", "thirtieth", "thirty-?first"]
date_regex = "(Jan(uary)?|Feb(r?uary)?|Mar(ch)?|Apr(il)?|May|Jun(e)?|Jul(y)?|Aug(ust)?|Sept?(ember)?|Oct(ober)?|Nov(ember)?|Dec(ember)?) ([0-9]+(th|nd|st|rd)?|#{ordinals.join("|")})"
bier_regex = /((Biers|Beers) for #{date_regex})|#{date_regex} (biers|beers)/i
this_week_start = bier_candidates.select { |nd| nd.to_s =~ bier_regex}.first
if this_week_start
  parent = this_week_start.parent
  current = parent.next_sibling
  while current.inner_html.strip.blank?
    current = current.next_sibling
  end
  while !current.inner_html.strip.blank?
    this_week << current.inner_html.strip
    current = current.next_sibling
  end
end

this_week = this_week.sort

to_write = YAML.dump([up_and_coming, this_week])
if to_write != target_memory
  f = File.new(target_memory_path, "w+")
  f.write(to_write)
  f.close

  Twitter.configure do |config|
    config.consumer_key = twitter_config['consumer_key']
    config.consumer_secret = twitter_config['consumer_secret']
    config.oauth_token = twitter_config['oauth_token']
    config.oauth_token_secret = twitter_config['oauth_token_secret']
  end

  def twitten(txt, tail)
    combined = txt + tail
    if combined.size > 140
      ellip = ".."
      ntxt = txt[0.. txt.size - ((combined.size - 139) + ellip.size)]
      combined = ntxt + ellip + tail
    end
    combined
  end

  date_str = Time.now.strftime("%b %d").upcase
  attribution = " http://www.bierbrewery.com/"
  upcoming_text = "#{date_str} UPCOMING: " + up_and_coming.collect { |bier, desc| "#{bier}: #{desc}" }.join(",") 
  this_week_text = "#{date_str} BIERS: " + this_week.join(",")
  Twitter.update(twitten(upcoming_text, attribution))
  Twitter.update(twitten(this_week_text, attribution))
end

