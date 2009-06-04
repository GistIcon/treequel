#!/usr/bin/env ruby

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent.parent

	libdir = basedir + "lib"

	$LOAD_PATH.unshift( libdir ) unless $LOAD_PATH.include?( libdir )
}

begin
	require 'spec'
	require 'spec/lib/constants'
	require 'spec/lib/helpers'

	require 'treequel/branch'
	require 'treequel/branchset'
rescue LoadError
	unless Object.const_defined?( :Gem )
		require 'rubygems'
		retry
	end
	raise
end


include Treequel::TestConstants
include Treequel::Constants

#####################################################################
###	C O N T E X T S
#####################################################################

describe Treequel::Branch do
	include Treequel::SpecHelpers

	before( :all ) do
		setup_logging( :fatal )
	end

	after( :all ) do
		reset_logging()
	end

	before( :each ) do
		@directory = mock( "treequel directory", :get_entry => :an_entry_hash )
	end


	it "can be constructed from a DN" do
		@directory.should_receive( :rdn_to ).with( TEST_PEOPLE_DN ).
			and_return( TEST_PEOPLE_RDN )
		@directory.should_receive( TEST_PEOPLE_DN_ATTR ).with( TEST_PEOPLE_DN_VALUE ).and_return do 
			args = [@directory, TEST_PEOPLE_DN_ATTR, TEST_PEOPLE_DN_VALUE, TEST_BASE_DN]
			Treequel::Branch.new( *args ) 
		end

		branch = Treequel::Branch.new_from_dn( TEST_PEOPLE_DN, @directory )
		branch.dn.should == TEST_PEOPLE_DN
	end

	it "can be constructed from an entry returned from LDAP::Conn.search2"  do
		entry = {
			'dn'                => [TEST_PERSON_DN],
			TEST_PERSON_DN_ATTR => TEST_PERSON_DN_VALUE,
		}
		branch = Treequel::Branch.new_from_entry( entry, @directory )

		branch.rdn_attribute.should == TEST_PERSON_DN_ATTR
		branch.rdn_value.should == TEST_PERSON_DN_VALUE
		branch.entry.should == entry
	end


	describe "instances" do

		before( :each ) do
			@branch = Treequel::Branch.new(
				@directory, 
				TEST_HOSTS_DN_ATTR, 
				TEST_HOSTS_DN_VALUE,
				TEST_BASE_DN
			  )

			@schema = mock( "treequel schema" )
			@entry = mock( "entry object" )
			@directory.stub!( :schema ).and_return( @schema )
			@directory.stub!( :get_entry ).and_return( @entry )
			@attribute_type = mock( "schema attribute type object" )
		end


		it "knows what its RDN is" do
			@branch.rdn.should == TEST_HOSTS_RDN
		end

		it "knows what its DN is" do
			@branch.dn.should == TEST_HOSTS_DN
		end

		it "fetch their LDAP::Entry from the directory if they don't already have one" do
			@directory.should_receive( :get_entry ).with( @branch ).exactly( :once ).
				and_return( :the_entry )

			@branch.entry.should == :the_entry
			@branch.entry.should == :the_entry
		end

		it "returns a human-readable representation of itself for #inspect" do
			@directory.should_not_receive( :get_entry ) # shouldn't try to load the entry for #inspect

			rval = @branch.inspect

			rval.should =~ /#{TEST_HOSTS_DN_ATTR}/i
			rval.should =~ /#{TEST_HOSTS_DN_VALUE}/
			rval.should =~ /#{TEST_BASE_DN}/
			rval.should =~ /\bnil\b/
		end


		it "implement a proxy method that allow for creation of sub-branches" do
			rval = @branch.cn( 'rondori' )
			rval.dn.should == "cn=rondori,#{TEST_HOSTS_DN}"

			rval2 = rval.ou( 'Config' )
			rval2.dn.should == "ou=Config,cn=rondori,#{TEST_HOSTS_DN}"
		end

		it "don't try to create sub-branches for method calls with more than one parameter" do
			lambda {
				@branch.dc( 'sbc', 'glar' )
			}.should raise_error( ArgumentError, /wrong number of arguments/ )
		end


		it "can return all of its immediate children as Branches" do
			@directory.should_receive( :search ).
				with( @branch, :one, '(objectClass=*)' ).
				and_return([ :the_children ])
			@branch.children.should == [ :the_children ]
		end

		it "can return its parent as a Branch" do
			parent_branch = stub( "parent branch object" )
			@branch.should_receive( :class ).and_return( Treequel::Branch )
			Treequel::Branch.should_receive( :new_from_dn ).with( TEST_BASE_DN, @directory ).
				and_return( parent_branch )
			@branch.parent.should == parent_branch
		end


		it "can construct a Treequel::Branchset that uses it as its base" do
			branchset = stub( "branchset" )
			Treequel::Branchset.should_receive( :new ).with( @branch ).
				and_return( branchset )

			@branch.branchset.should == branchset
		end

		it "can create a filtered Treequel::Branchset for itself" do
			branchset = mock( "filtered branchset" )
			Treequel::Branchset.should_receive( :new ).with( @branch ).
				and_return( branchset )
			branchset.should_receive( :filter ).with( {:cn => 'acme'} ).
				and_return( :a_filtered_branchset )

			@branch.filter( :cn => 'acme' ).should == :a_filtered_branchset
		end

		it "doesn't restrict the number of arguments passed to #filter (bugfix)" do
			branchset = mock( "filtered branchset" )
			Treequel::Branchset.should_receive( :new ).with( @branch ).
				and_return( branchset )
			branchset.should_receive( :filter ).with( :uid, [:glumpy, :grumpy, :glee] ).
				and_return( :a_filtered_branchset )

			@branch.filter( :uid, [:glumpy, :grumpy, :glee] ).should == :a_filtered_branchset
		end

		it "can create a scoped Treequel::Branchset for itself" do
			branchset = mock( "scoped branchset" )
			Treequel::Branchset.should_receive( :new ).with( @branch ).
				and_return( branchset )
			branchset.should_receive( :scope ).with( :onelevel ).
				and_return( :a_scoped_branchset )

			@branch.scope( :onelevel ).should == :a_scoped_branchset
		end

		it "can create a selective Treequel::Branchset for itself" do
			branchset = mock( "selective branchset" )
			Treequel::Branchset.should_receive( :new ).with( @branch ).
				and_return( branchset )
			branchset.should_receive( :select ).with( :uid, :l, :familyName, :givenName ).
				and_return( :a_selective_branchset )

			@branch.select( :uid, :l, :familyName, :givenName ).should == :a_selective_branchset
		end

		it "knows which objectClasses it has" do
			oc_attr = mock( "objectClass attributeType object" )
			@schema.should_receive( :attribute_types ).and_return({ :objectClass => oc_attr })
			oc_attr.should_receive( :single? ).and_return( false )
			@entry.should_receive( :[] ).with( 'objectClass' ).at_least( :once ).
				and_return([ 'ou', 'cn' ])

			@schema.should_receive( :object_classes ).twice.and_return({
				:ou => :ou_objectclass,
				:cn => :cn_objectclass,
			})

			@branch.object_classes.should == [ :ou_objectclass, :cn_objectclass ]
		end

		it "can return the set of all its MUST attributeTypes based on which objectClasses it has" do
			oc1 = mock( "first objectclass" )
			oc2 = mock( "second objectclass" )

			@branch.should_receive( :object_classes ).and_return([ oc1, oc2 ])
			oc1.should_receive( :must ).and_return([ :cn, :uid ])
			oc2.should_receive( :must ).and_return([ :cn, :l ])

			must_attrs = @branch.must_attribute_types
			must_attrs.should have( 3 ).members
			must_attrs.should include( :cn, :uid, :l )
		end

		it "can return the set of all its MAY attributeTypes based on which objectClasses it has" do
			oc1 = mock( "first objectclass" )
			oc2 = mock( "second objectclass" )

			@branch.should_receive( :object_classes ).and_return([ oc1, oc2 ])
			oc1.should_receive( :may ).and_return([ :description, :mobilePhone ])
			oc2.should_receive( :may ).and_return([ :chunktype ])

			must_attrs = @branch.may_attribute_types
			must_attrs.should have( 3 ).members
			must_attrs.should include( :description, :mobilePhone, :chunktype )
		end

		it "can return the set of all of its valid attributeTypes, which is a union of its " +
		   "MUST and MAY attributes" do
			@branch.should_receive( :must_attribute_types ).
				and_return([ :cn, :l, :uid ])
			@branch.should_receive( :may_attribute_types ).
				and_return([ :description, :mobilePhone, :chunktype ])

			all_attrs = @branch.valid_attribute_types

			all_attrs.should have( 6 ).members
			all_attrs.should include( :cn, :uid, :l, :description, :mobilePhone, :chunktype )
		end


		it "can be moved to a new location within the directory"


		it "can be deleted from the directory" do
			@directory.should_receive( :delete ).with( @branch )
			@branch.delete
		end


		it "can create children under itself" do
			newattrs = { :cn => 'Chilly T' }
			newbranch = stub( "child branch object" )
			@directory.should_receive( :create ).with( @branch, TEST_PERSON_RDN, newattrs ).
				and_return( newbranch )
			@branch.create( TEST_PERSON_RDN, newattrs ).should == newbranch
		end


		it "can copy itself to a sibling entry" do
			newbranch = stub( "copied sibling branch" )
			@directory.should_receive( :copy ).with( @branch, TEST_PERSON2_DN, {} ).
				and_return( newbranch )
			@branch.copy( TEST_PERSON2_DN ).should == newbranch
		end


		it "can copy itself to a sibling entry with attribute changes" do
			newattrs = { :sn => "Michaels", :firstName => 'George' }
			newbranch = stub( "copied sibling branch" )
			@directory.should_receive( :copy ).with( @branch, TEST_PERSON2_RDN, newattrs ).
				and_return( newbranch )
			@branch.copy( TEST_PERSON2_RDN, newattrs ).should == newbranch
		end


		it "can modify its entry's attributes" do
			attributes = {
				:displayName => 'Chilly T. Penguin',
				:description => "A chilly little penguin.",
			}

			@directory.should_receive( :modify ).with( @branch, attributes )

			@branch.modify( attributes )
		end


		### Attribute reader
		describe "index fetch operator" do

			it "fetches a multi-value attribute as an Array" do
				@schema.should_receive( :attribute_types ).and_return({ :glumpy => @attribute_type })
				@attribute_type.should_receive( :single? ).and_return( false )
				@entry.should_receive( :[] ).with( 'glumpy' ).at_least( :once ).
					and_return([ 'glumpa1', 'glumpa2' ])

				@branch[ :glumpy ].should == [ 'glumpa1', 'glumpa2' ]
			end

			it "fetches a single-value attribute as a scalar" do
				@schema.should_receive( :attribute_types ).and_return({ :glumpy => @attribute_type })
				@attribute_type.should_receive( :single? ).and_return( true )
				@entry.should_receive( :[] ).with( 'glumpy' ).at_least( :once ).
					and_return([ 'glumpa1' ])

				@branch[ :glumpy ].should == 'glumpa1'
			end

			it "returns nil if there is no such attribute in the schema" do
				@schema.should_receive( :attribute_types ).and_return({})
				@branch[ :glumpy ].should == nil
			end

			it "returns nil if record doesn't have the attribute set" do
				@schema.should_receive( :attribute_types ).and_return({ :glumpy => @attribute_type })
				@entry.should_receive( :[] ).with( 'glumpy' ).and_return( nil )
				@branch[ :glumpy ].should == nil
			end

			it "caches the value fetched from its entry" do
				@schema.stub!( :attribute_types ).and_return({ :glump => @attribute_type })
				@attribute_type.stub!( :single? ).and_return( true )
				@entry.should_receive( :[] ).with( 'glump' ).once.and_return( [:a_value] )
				2.times { @branch[ :glump ] }
			end

		end

		### Attribute writer
		describe "index set operator" do

			it "writes a single value attribute via its directory" do
				@directory.should_receive( :modify ).with( @branch, { 'glumpy' => ['gits'] } )
				@entry.should_receive( :[]= ).with( 'glumpy', ['gits'] )
				@branch[ :glumpy ] = 'gits'
			end

			it "writes multiple attribute values via its directory" do
				@directory.should_receive( :modify ).with( @branch, { 'glumpy' => ['gits', 'crumps'] } )
				@entry.should_receive( :[]= ).with( 'glumpy', ['gits', 'crumps'] )
				@branch[ :glumpy ] = [ 'gits', 'crumps' ]
			end

			it "clears the cache after a successful write" do
				@schema.stub!( :attribute_types ).and_return({ :glorpy => @attribute_type })
				@attribute_type.stub!( :single? ).and_return( true )
				@entry.should_receive( :[] ).with( 'glorpy' ).and_return( [:firstval], [:secondval] )

				@directory.should_receive( :modify ).with( @branch, {'glorpy' => ['chunks']} )
				@entry.should_receive( :[]= ).with( 'glorpy', ['chunks'] )

				@branch[ :glorpy ].should == :firstval
				@branch[ :glorpy ] = 'chunks'
				@branch[ :glorpy ].should == :secondval
			end
		end
	end


end


# vim: set nosta noet ts=4 sw=4:
