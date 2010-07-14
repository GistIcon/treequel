#!/usr/bin/env ruby

require 'ldap'
require 'ldap/schema'

require 'treequel'
require 'treequel/constants'
require 'treequel/mixins'


# This is an object that is used to parse and query a directory's schema
# 
# == Authors
# 
# * Michael Granger <ged@FaerieMUD.org>
# * Mahlon E. Smith <mahlon@martini.nu>
# 
# :include: LICENSE
#
#--
#
# Please see the file LICENSE in the base directory for licensing details.
#
class Treequel::Schema
	include Treequel::Loggable,
	        Treequel::Constants::Patterns

	require 'treequel/schema/table'
	require 'treequel/schema/objectclass'
	require 'treequel/schema/attributetype'
	require 'treequel/schema/matchingrule'
	require 'treequel/schema/matchingruleuse'
	require 'treequel/schema/ldapsyntax'


	#################################################################
	###	C L A S S   M E T H O D S
	#################################################################

	### Parse the given +oidstring+ into an Array of OIDs, with Strings for numeric OIDs and
	### Symbols for aliases.
	def self::parse_oids( oidstring )
		return [] unless oidstring

		unless /^ #{OIDS} $/x.match( oidstring.strip )
			raise Treequel::ParseError, "couldn't find an OIDLIST in %p" % [ oidstring ]
		end

		oids = $MATCH
		# Treequel.logger.debug "  found OIDs: %p" % [ oids ]

		# If it's an OIDLIST, strip off leading and trailing parens and whitespace, then split 
		# on ' $ ' and parse each OID
		if oids.include?( '$' )
			parse_oid = self.method( :parse_oid )
			return $MATCH[1..-2].strip.split( /#{WSP} #{DOLLAR} #{WSP}/x ).collect( &parse_oid )

		else
			return [ self.parse_oid(oids) ]

		end

	end


	### Parse a single OID into either a numeric OID string or a Symbol.
	def self::parse_oid( oidstring )
		if oidstring =~ NUMERICOID
			return oidstring.untaint
		else
			return oidstring.untaint.to_sym
		end
	end


	### Parse the given short +names+ string (a 'qdescrs' in the BNF) into an Array of zero or
	### more Strings.
	def self::parse_names( names )
		# Treequel.logger.debug "  parsing NAME attribute from: %p" % [ names ]

		# Unspecified
		if names.nil?
			# Treequel.logger.debug "    no NAME attribute"
			return []

		# Multi-value
		elsif names =~ /#{LPAREN} #{WSP} (#{QDESCRLIST}) #{WSP} #{RPAREN}/x
			# Treequel.logger.debug "    parsing a NAME list from %p" % [ $1 ]
			return $1.scan( QDESCR ).collect {|qd| qd[1..-2].untaint.to_sym }

		# Single-value
		else
			# Return the name without the quotes
			# Treequel.logger.debug "    dequoting a single NAME"
			return [ names[1..-2].untaint.to_sym ]
		end
	end


	### Return a new string which is +desc+ with quotes stripped and any escaped characters 
	### un-escaped.
	def self::unquote_desc( desc )
		return nil if desc.nil?
		return desc.gsub( QQ, "'" ).gsub( QS, '\\' )[ 1..-2 ]
	end


	### Return a description of the given +descriptors+ suitable for inclusion in 
	### an RFC4512-style schema description entry.
	### @param [Array<String>] descriptors  an Array of descriptors
	### @return [String] the 'qdescrs' text
	def self::qdescrs( *descriptors )
		descriptors.flatten!
		if descriptors.length > 1
			return "( %s )" % [ descriptors.collect {|str| self.qdstring(str) }.join(" ") ]
		else
			return self.qdstring( descriptors.first )
		end
	end


    # qdstring = SQUOTE dstring SQUOTE
    # dstring = 1*( QS / QQ / QUTF8 )   ; escaped UTF-8 string
    # 
    # QQ =  ESC %x32 %x37 ; "\27"
    # QS =  ESC %x35 ( %x43 / %x63 ) ; "\5C" / "\5c"
    # 
    # ; Any UTF-8 encoded Unicode character
    # ; except %x27 ("\'") and %x5C ("\")
    # QUTF8    = QUTF1 / UTFMB

	### Escape and quote the specified +string+ according to the rules in 
	### RFC4512/2252.
	### @param [String] string  the unescaped UTF8 string
	### @return [String] the string after quoting and escaping
	def self::qdstring( string )
		return "'%s'" % [ string.to_s.gsub(/\\/, '\\\\5c').gsub(/'/, '\\\\27') ]
	end


	### Return a description of the given +oids+ suitable for inclusion in 
	### an RFC4512-style schema description entry.
	### @param [Array<String>] oids  an Array of numeric or symbolic OIDs
	### @return [String] the oid list text
	def self::oids( *oids )
		oids.flatten!
		if oids.length > 1
			return "( %s )" % [ oids.join(" $ ") ]
		else
			return oids.first
		end
	end



	#################################################################
	###	I N S T A N C E   M E T H O D S
	#################################################################

	### Create a new Treequel::Schema from the specified +hash+. The +hash+ should be of the same
	### form as the one returned by LDAP::Conn.schema, i.e., a Hash of Arrays associated with the
	### keys "objectClasses", "ldapSyntaxes", "matchingRuleUse", "attributeTypes", and 
	### "matchingRules".
	def initialize( hash )
		@object_classes     = self.parse_objectclasses( hash['objectClasses'] )
		@attribute_types    = self.parse_attribute_types( hash['attributeTypes'] )
		@ldap_syntaxes      = self.parse_ldap_syntaxes( hash['ldapSyntaxes'] )
		@matching_rules     = self.parse_matching_rules( hash['matchingRules'] )
		@matching_rule_uses = self.parse_matching_rule_uses( hash['matchingRuleUse'] )
	end


	######
	public
	######

	# The Hash of Treequel::Schema::ObjectClass objects, keyed by OID and any associated NAME 
	# attributes (as Symbols), that describes the objectClasses in the directory's schema.
	attr_reader :object_classes

	# The hash of Treequel::Schema::AttributeType objects, keyed by OID and any associated NAME
	# attributes (as Symbols), that describe the attributeTypes in the directory's schema.
	attr_reader :attribute_types

	# The hash of Treequel::Schema::LDAPSyntax objects, keyed by OID, that describe the 
	# syntaxes in the directory's schema.
	attr_reader :ldap_syntaxes

	# The hash of Treequel::Schema::MatchingRule objects, keyed by OID and any associated NAME
	# attributes (as Symbols), that describe the matchingRules int he directory's schema.
	attr_reader :matching_rules

	# The hash of Treequel::Schema::MatchingRuleUse objects, keyed by OID and any associated NAME
	# attributes (as Symbols), that describe the attributes to which a matchingRule can be applied.
	attr_reader :matching_rule_uses
	alias_method :matching_rule_use, :matching_rule_uses


	### Return a human-readable representation of the object suitable for debugging.
	def inspect
		ivar_descs = self.instance_variables.sort.collect do |ivar|
			len = self.instance_variable_get( ivar ).length
			"%d %s" % [ len, ivar.gsub(/_/, ' ')[1..-1] ]
		end
		return %{#<%s:0x%0x %s>} % [
			self.class.name,
			self.object_id / 2,
			ivar_descs.join(', '),
		]
	end


	#########
	protected
	#########

	### Parse the given objectClass +descriptions+ into Treequel::Schema::ObjectClass objects, and
	### return them as a Hash keyed both by numeric OID and by each of its NAME attributes (if it
	### has any).
	def parse_objectclasses( descriptions )
		return descriptions.inject( Treequel::Schema::Table.new ) do |table, desc|
			oc = Treequel::Schema::ObjectClass.parse( self, desc ) or
				raise Treequel::Error, "couldn't create an objectClass from %p" % [ desc ]

			table[ oc.oid ] = oc
			oc.names.inject( table ) {|h, name| h[name] = oc; h }

			table
		end
	end


	### Parse the given attributeType +descriptions+ into Treequel::Schema::AttributeType objects
	### and return them as a Hash keyed both by numeric OID and by each of its NAME attributes 
	### (if it has any).
	def parse_attribute_types( descriptions )
		return descriptions.inject( Treequel::Schema::Table.new ) do |table, desc|
			attrtype = Treequel::Schema::AttributeType.parse( self, desc ) or
				raise Treequel::Error, "couldn't create an attributeType from %p" % [ desc ]

			table[ attrtype.oid ] = attrtype
			attrtype.names.inject( table ) {|h, name| h[name] = attrtype; h }

			table
		end
	end


	### Parse the given LDAP syntax +descriptions+ into Treequel::Schema::LDAPSyntax objects and
	### return them as a Hash keyed by numeric OID.
	def parse_ldap_syntaxes( descriptions )
		descriptions ||= []
		return descriptions.inject( Treequel::Schema::Table.new ) do |table, desc|
			syntax = Treequel::Schema::LDAPSyntax.parse( self, desc ) or
				raise Treequel::Error, "couldn't create an LDAPSyntax from %p" % [ desc ]

			table[ syntax.oid ] = syntax
			table
		end
	end


	### Parse the given matchingRule +descriptions+ into Treequel::Schema::MatchingRule objects
	### and return them as a Hash keyed both by numeric OID and by each of its NAME attributes 
	### (if it has any).
	def parse_matching_rules( descriptions )
		descriptions ||= []
		return descriptions.inject( Treequel::Schema::Table.new ) do |table, desc|
			rule = Treequel::Schema::MatchingRule.parse( self, desc ) or
				raise Treequel::Error, "couldn't create an matchingRule from %p" % [ desc ]

			table[ rule.oid ] = rule
			rule.names.inject( table ) {|h, name| h[name] = rule; h }

			table
		end
	end


	### Parse the given matchingRuleUse +descriptions+ into Treequel::Schema::MatchingRuleUse objects
	### and return them as a Hash keyed both by numeric OID and by each of its NAME attributes 
	### (if it has any).
	def parse_matching_rule_uses( descriptions )
		descriptions ||= []
		return descriptions.inject( Treequel::Schema::Table.new ) do |table, desc|
			ruleuse = Treequel::Schema::MatchingRuleUse.parse( self, desc ) or
				raise Treequel::Error, "couldn't create an matchingRuleUse from %p" % [ desc ]

			table[ ruleuse.oid ] = ruleuse
			ruleuse.names.inject( table ) {|h, name| h[name] = ruleuse; h }

			table
		end
	end


end # class Treequel::Schema

