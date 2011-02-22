#!/usr/bin/env ruby
# coding: utf-8

require 'treequel'
require 'treequel/model'
require 'treequel/mixins'
require 'treequel/constants'


# Mixin that provides Treequel::Model characteristics to a mixin module.
module Treequel::Model::ObjectClass
	include Treequel::HashUtilities
	extend Treequel::Delegation


	### Extension callback -- add data structures to the extending +mod+.
	### @param [Module] mod  the mixin module to be extended
	def self::extended( mod )
		mod.instance_variable_set( :@model_class, Treequel::Model )
		mod.instance_variable_set( :@model_objectclasses, [] )
		mod.instance_variable_set( :@model_bases, [] )
		super
	end


	### Inclusion callback -- Methods should be applied to the module rather than an instance.
	### Warn the user if they use include() and extend() instead.
	def self::included( mod )
		warn "extending %p rather than appending features to it" % [ mod ]
		mod.extend( self )
	end


	#################################################################
	###	I N S T A N C E   M E T H O D S
	#################################################################

	# Delegate Branchset methods through #search to allow ObjectClass.filter as a shortcut for
	# ObjectClass.search.filter
	def_method_delegators :search, 
		:collection, :map, :to_hash, :each, :first, 
		:filter, :scope, :select, :limit, :timeout, :as, :from


	### Declare which Treequel::Model subclasses the mixin will register itself with. If this is
	### used, it should be declared *before* declaring the mixin's bases and/or objectClasses.
	def model_class( mclass=nil )
		if mclass

			# If there were already registered objectclasses, remove them from the previous
			# model class
			unless @model_objectclasses.empty? && @model_bases.empty?
				Treequel.log.warn "%p: model_class should come before model_objectclasses" % [ self ]
				@model_class.unregister_mixin( self )
				mclass.register_mixin( self )
			end
			@model_class = mclass
		end

		return @model_class
	end


	### Set or get objectClasses that the mixin requires. Also registers the mixin with
	### Treequel::Model.
	### 
	### @param [Array<#to_sym>] objectclasses  the objectClasses the mixin will apply to, as an
	###         array of Symbols (or objects that respond to #to_sym)
	### @return [Array<Symbol>] the objectClasses that the module requires
	def model_objectclasses( *objectclasses )
		unless objectclasses.empty?
			@model_objectclasses = objectclasses.map( &:to_sym )
			@model_class.register_mixin( self )
		end
		return @model_objectclasses.dup
	end


	### Set or get base DNs that the mixin applies to.
	def model_bases( *base_dns )
		unless base_dns.empty?
			@model_bases = base_dns.collect {|dn| dn.gsub(/\s+/, '') }
			@model_class.register_mixin( self )
		end

		return @model_bases.dup
	end


	### @overload create( dn, entryhash={} )
	###   Create a new instance of the mixin's model_class in the model_class's default
	###   directory with the given +dn+ and the objectclasses specified by the mixin. If the
	###   optional +entryhash+ is given, it will be used as the initial attributes of the
	###   new entry.
	###   @param [#to_s] dn                       the DN of the new model object
	###   @param [Hash] entryhash                 attributes to set on the new entry
	### @overload create( directory, dn, entryhash={} )
	###   Create a new instance of the mixin's model_class in the specified +directory+
	###   with the given +dn+ and the objectclasses specified by the mixin. If the
	###   optional +entryhash+ is given, it will be used as the initial attributes of the
	###   new entry.
	###   @param [Treequel::Directory] directory  the directory to create the entry in (optional)
	###   @param [#to_s] dn                       the DN of the new model object
	###   @param [Hash] entryhash                 attributes to set on the new entry
	def create( directory, dn=nil, entryhash={} )

		# Shift the arguments if the first one isn't a directory
		unless directory.is_a?( Treequel::Directory )
			entryhash = dn || {}
			dn = directory
			directory = self.model_class.directory
		end

		entryhash = stringify_keys( entryhash )

		# Add the objectclasses from the mixin
		entryhash['objectClass'] ||= []
		entryhash['objectClass'].collect!( &:to_s )
		entryhash['objectClass'] |= self.model_objectclasses.map( &:to_s )

		# Add all the attribute pairs from the RDN bit of the DN to the entry
		rdn_pair, _ = dn.split( /\s*,\s*/, 2 )
		rdn_pair.split( /\+/ ).each do |attrpair|
			k, v = attrpair.split( /\s*=\s*/ )
			entryhash[ k ] ||= []
			entryhash[ k ] << v unless entryhash[ k ].include?( v )
		end

		return self.model_class.new( directory, dn, entryhash )
	end


	### Return a Branchset (or BranchCollection if the receiver has more than one
	### base) that can be used to search the given +directory+ for entries to which
	### the receiver applies.
	###
	### @param [Treequel::Directory] directory  the directory to search; if not given, this defaults
	###                                         to the directory associated with the module's
	###                                         model_class.
	### @return [Treequel::Branchset, Treequel::BranchCollection]  the encapsulated search
	def search( directory=nil )
		directory ||= self.model_class.directory
		bases = self.model_bases
		objectclasses = self.model_objectclasses

		raise Treequel::ModelError, "%p has no search criteria defined" % [ self ] if
			bases.empty? && objectclasses.empty?

		Treequel.log.debug "Creating search for %p using model class %p" %
			[ self, self.model_class ]

		# Start by making a Branchset or BranchCollection for the mixin's bases. If
		# the mixin doesn't have any bases, just use the base DN of the directory
		# to be searched
		bases = [directory.base_dn] if bases.empty?
		search = bases.
			map {|base| self.model_class.new(directory, base).branchset }.
			inject {|branch1,branch2| branch1 + branch2 }

		Treequel.log.debug "Search branch after applying bases is: %p" % [ search ]

		return self.model_objectclasses.inject( search ) do |branchset, oid|
			Treequel.log.debug "  adding filter for objectClass=%s to %p" % [ oid, branchset ]
			branchset.filter( :objectClass => oid )
		end
	end

end # Treequel::Model::ObjectClass

