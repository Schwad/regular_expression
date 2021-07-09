# RegularExpression

[![Build Status](https://github.com/kddeisz/regular_expression/workflows/Main/badge.svg)](https://github.com/kddeisz/regular_expression/actions)

A regular expression engine written in Ruby.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "regular_expression"
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install regular_expression

## Usage

To create a regular expression pattern, use:

```ruby
pattern = RegularExpression::Pattern.new("ab?c")
```

Patterns can be queried for whether or not they match a test string, as in:

```ruby
pattern.match?("abc") # => true
pattern.match?("ac") # => true
pattern.match?("ab") # => false
```

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `bundle exec rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kddeisz/regular_expression.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
