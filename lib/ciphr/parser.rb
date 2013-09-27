require 'parslet'

class Ciphr::Parser < Parslet::Parser
	rule(:spaces)      { match('\s').repeat(1) }
	rule(:spaces?)     { spaces.maybe }

	rule(:name) { (match('[a-z]') >> match('[a-z0-9]').repeat).as(:name) }	
	rule(:literal) { (b16 | b64 | string | file) }
	rule(:file) { str('@') >> (	string | match('[^ ()\[\]{},|]' ).repeat ).as(:file) } 
	rule(:string) { str('"') >> ( str('\\') >> any | str('"').absent? >> any ).repeat.maybe.as(:string) >> str('"') }
	rule(:b16) { str('0x') >> match('[0-9a-f]').repeat(1).as(:b16) }
	rule(:b64) { str('=') >> match('[0-9a-zA-Z+/=]').repeat(1).as(:b64) }
	rule(:call) { str('~').maybe.as(:invert) >> name.as(:name) >> (str('(') >> (expression >> (str(',') >> expression).repeat).maybe.as(:arguments) >> str(')')).maybe }
	rule(:expression) { ( ( call | literal) >> ( str('|') | str(' ').repeat >> ( call | literal ) ).repeat ).as(:operations) }

	root :expression
end

class Ciphr::Transformer < Parslet::Transform
	rule(:name => simple(:v)) { v }	
	rule(:string => simple(:v)) {|d| Ciphr::Functions::StringReader.new({:string => d[:v]},[]) }
	rule(:b64 => simple(:v)) {|d| Ciphr::Functions::Base64.new({}, [Ciphr::Functions::StringReader.new({:string => d[:v]},[])]).tap{|f| f.invert = true} }
	rule(:b16 => simple(:v)) {|d| Ciphr::Functions::Base16.new({}, [Ciphr::Functions::StringReader.new({:string => d[:v]},[])]).tap{|f| f.invert = true} }
	rule(:arguments => sequence(:arguments), :invert => simple(:invert), :name => simple(:name)) {|d| transform_call(d) }
	rule(:arguments => simple(:arguments), :invert => simple(:invert), :name => simple(:name)) {|d| transform_call(d) }
	rule(:invert => simple(:invert), :name => simple(:name)) {|d| transform_call(d) }
	rule(:operations => simple(:operations)) {|d| transform_operations(d)}
	rule(:operations => sequence(:operations)) {|d| transform_operations(d)}	

	def self.transform_operations(d)
		operations = [d[:operations]].flatten
		if operations[0].args.size < operations[0].params.size
			operations.unshift(Ciphr::Functions::StdInReader.new({},[]))
		end
		operations.inject{|m,f| f.args = [f.args||[]].flatten.unshift(m); f }
	end

	def self.transform_call(d)
		klass, options = Ciphr::Functions[d[:name].to_s]
		f = klass.new(options, [d[:arguments]||[]].flatten)
		f.invert = true if d[:invert]
		f
	end
end