#!/usr/bin/env ruby

require 'mail'
require 'zip'

class Parser
  attr_accessor :filename

  def self.parse(filename)
    new(filename).parse
  end

  def initialize(filename)
    @filename = filename
  end

  def method_name
    "parse_#{File.extname(filename)[1..-1]}"
  end

  def parse
    public_send(method_name) if respond_to?(method_name)

    parse_mailboxes
  end

  def parse_mailboxes
    mailboxes.each do |mailbox|
      parse_mailbox(mailbox).each do |message|
        puts message.from
      end
    end
  end

  def mailboxes
    Dir.glob(File.join('tmp', '**', '*.mbox'))
  end

  def parse_mailbox(mailbox)
    message = nil
    Enumerator.new do |yielder|
      IO.foreach(mailbox) do |line|
        if (line.match(/\AFrom /))
          yielder << parse_message(message) if message
          message = ''
        else
          message << line.sub(/^\>From/, 'From')
        end
      end
    end
  end

  def parse_message(message)
    Mail.new(message)
  end

  def parse_zip
    Zip::File.open(filename) do |zip_file|
      zip_file.each do |f|
        destination = File.join('tmp', f.name)
        FileUtils.mkdir_p(File.dirname(destination))
        zip_file.extract(f, destination) unless File.exist?(destination)
      end
    end
  end
end

def main
  ARGV.each do |arg|
    Parser.parse(arg)
  end
end

main
