#!/usr/bin/env ruby

require 'csv'
require 'mail'
require 'zip'

class Parser
  attr_accessor :filename

  EMAIL_ADDRESS_PATTERN = %r{
    (
      \A
      (?<email>[^\s]+)
      \z
    )
    |
    (
      \A
      "?(?<name>.*?)?"?
      \s+
      \<
      (?<email>.+)
      \>
      \z
    )
  }xi

  def self.parse(filename)
    new(filename).parse
  end

  def initialize(filename)
    @filename = filename
    @addresses = []
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
        addresses(message).each do |address|
          @addresses << address
        end
      end
    end

    @addresses
  end

  def addresses(mail)
    Enumerator.new do |yielder|
      yielder << mail[:envelope_from]
      yielder << mail[:from].formatted
      yielder << mail[:to].formatted
      yielder << mail[:cc].formatted if mail[:cc]
    end.map do |address_container|
      next unless address_container

      address_container.map do |address|
        address
      end
    end.flatten.compact
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
  filename = File.join('tmp', 'addresses.csv')
  CSV.open(filename, 'w') do |csv|
    csv << %w(
      address
      name
      email
    )

    ARGV.each do |arg|
      Parser.parse(arg).uniq.sort.each do |address|
        match = address.match(Parser::EMAIL_ADDRESS_PATTERN)
        csv << [
          address,
          match[:name],
          match[:email]
        ]
      end
    end
  end
end

main
