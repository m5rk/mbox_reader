#!/usr/bin/env ruby

require 'benchmark'
require 'csv'
require 'mail'
require 'zip'

class Parser
  attr_accessor \
    :addresses,
    :errors,
    :filename,
    :messages

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
    parser = new(filename)
    elapsed = Benchmark.realtime { parser.parse }

    puts %Q(
Elapsed: #{elapsed.round(2)} seconds
Addresses: #{parser.addresses.count}
Messages: #{parser.messages}
Errors: #{parser.errors}
    ).strip

    parser.addresses
  end

  def initialize(filename)
    @addresses = []
    @errors = 0
    @filename = filename
    @messages = 0
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
        begin
          date = message.date
          iter_addresses(message).each do |address|
            addresses << [address, date]
          end
        rescue StandardError => e
          @errors += 1
        end
      end
    end
  end

  def iter_addresses(message)
    Enumerator.new do |yielder|
      yielder << message[:envelope_from]
      yielder << message[:from].formatted
      yielder << message[:to].formatted if message[:to]
      yielder << message[:cc].formatted if message[:cc]
    end.map do |address_container|
      next unless address_container

      address_container.map do |address|
        address
      end
    end.flatten.compact
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
        FileUtils.mkdir_p(File.dirname(destination))
        zip_file.extract(f, destination) unless File.exist?(destination)
      end
    end
  end
end

def main
  Parser.reset

  # Extract addresses from each file in ARGV.
  addresses = []
  ARGV.map do |arg|
    addresses += Parser.parse(arg)
  end

  addresses = addresses.each_with_object({}) do |item, memo|
    address, date = item
    memo[address] ||= []
    memo[address] << date
  end.to_a.sort_by(&:first).map do |address, dates|
    match = address.match(Parser::EMAIL_ADDRESS_PATTERN) || {}
    most_recent_date = dates.compact.sort.last

    if most_recent_date
      most_recent_date = most_recent_date.to_date.to_s
    end

    [address, match[:name], match[:email], most_recent_date]
  end

  # Dump to csv.
  filename = File.join(Parser.dirname, 'addresses.csv')
  CSV.open(filename, 'w') do |csv|
    csv << %w(
      address
      name
      email
      most_recent_date
    )

    addresses.each do |address|
      csv << address.map { |item| item.strip if item }
    end
  end
end

main
