#!/usr/bin/env ruby

require 'csv'
require 'mail'
require 'zip'

class Parser
  attr_accessor :filename

  def self.dirname
    File.join(File.dirname(__FILE__), 'tmp')
  end

  def self.reset
    FileUtils.rmtree(dirname) if Dir.exists?(dirname)

    FileUtils.mkdir_p(dirname)
  end

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
    @messages = 0
    @errors = 0
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
      parse_mailbox(mailbox).each_with_index do |message, index|
        @messages += 1
        if (index + 1) % 1000 == 0
          puts index + 1
        end
        addresses(message).each do |address|
          @addresses << address
        end
      end
    end

    puts %Q(
Addresses: #{@addresses.count}
Messages: #{@messages.count}
Errors: #{@errors.count}
)

    @addresses
  end

  def addresses(mail)
    Enumerator.new do |yielder|
      yielder << mail[:envelope_from]
      yielder << mail[:from].formatted
      yielder << mail[:to].formatted if mail[:to]
      yielder << mail[:cc].formatted if mail[:cc]
    end.map do |address_container|
      next unless address_container

      address_container.map do |address|
        address
      end
    end.flatten.compact
  rescue StandardError => e
    @errors += 1

    []
  end

  def mailboxes
    Dir.glob(File.join(Parser.dirname, '**', '*.mbox'))
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

  def parse_mbox
    FileUtils.cp(filename, Parser.dirname)
  end

  def parse_zip
    Zip::File.open(filename) do |zip_file|
      zip_file.each do |f|
        destination = File.join(Parser.dirname, f.name)
        zip_file.extract(f, destination) unless File.exist?(destination)
      end
    end
  end
end

def main
  Parser.reset

  # Extract addresses from each file in ARGV.
  addresses = ARGV.map do |arg|
    Parser.parse(arg)
  end.flatten.compact.uniq.sort.map do |address|
    match = address.match(Parser::EMAIL_ADDRESS_PATTERN) || {}
    [address, match[:name], match[:email]]
  end

  # Dump to csv.
  filename = File.join(Parser.dirname, 'addresses.csv')
  CSV.open(filename, 'w') do |csv|
    csv << %w(
      address
      name
      email
    )

    addresses.each do |address|
      csv << address.map { |item| item.strip if item }
    end
  end
end

main
