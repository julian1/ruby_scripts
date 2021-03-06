#!/usr/bin/ruby

# Script to trace out the references of a geoserver configuration directory 
# and output useful configuration data

# This ought to make it easy to copy all needed files in one operation. 
# And to patch-up workspace and namespace references and jndi entries etc 

require 'rexml/document'
require 'rexml/xpath'
require 'find'


require 'optparse'
require 'yaml'


def create_oid_mappings( geoserver_config_dir )

  # scan the directory and create a set of mappings from object references
  # to their paths and xml structure 

  # the list of geoserver object identifiers 
  oids = {} 

  Find.find( geoserver_config_dir  ) do |path|

    # only take xml files
    next unless FileTest.file?(path)
    # next unless File.extname(path) == '.xml' or File.extname(path) == '.sld' 
    next unless File.extname(path) == '.xml'

    # puts "file #{path}"

    # get the id of the object represented by the file
    # this oid will be the first in the file
    file = File.new( path )
    doc = REXML::Document.new file
    oid = REXML::XPath.first( doc, "/*/id" )
    next unless oid 

    # puts " oid is #{oid.text}"

    # there are cases where same id will have several associated files 
    # eg. he gwc-layer id corresponds with the layer.xml file
    # so use a list
    if oids[ oid.text].nil? 
      oids[ oid.text ] = [ { doc: doc, path: path } ]
    else
      oids[ oid.text ] << { doc: doc, path: path }
      puts "duplicate object id #{path}   (#{oids[ oid.text ].first[:path]  })" 
    end
  end

  oids
end


## we may want to keep a hash through the recursion to keep track of
## whether we've already looked at a node.

def pad( depth )
  # format some common object types for pretty printing
  # pad recursion depth
  pad = ''
  depth.times { pad  += '  ' } 
  pad
end


def trace_oid( oids, oid, depth, options )

  # recursively trace out the objects 
  # there may be more than one file that has the same id (eg layer.xml and gwc-layer) 
  oids[ oid].each() do |object|

    node = object[:doc]
    path = object[:path]

    if REXML::XPath.first( node, "/GeoServerTileLayer" )
      puts "#{pad(depth)} *GeoServerTileLayer" 
      puts "#{pad(depth+1)} +name->#{REXML::XPath.first( node, '/GeoServerTileLayer/name').text}"


    elsif REXML::XPath.first( node, "/layer" )
      puts "#{pad(depth)} *layer #{path}" 
      puts "#{pad(depth+1)} +name->#{REXML::XPath.first( node, '/layer/name').text}"
      puts "#{pad(depth+1)} +type->#{REXML::XPath.first( node, '/layer/type').text}"
      enabled = REXML::XPath.first( node, '/layer/enabled')
      if enabled
        puts "#{pad(depth+1)} +enabled->#{enabled.text}"
      end

      ### we should check the gwc-layer from here,

    elsif REXML::XPath.first( node, "/featureType" )
      puts "#{pad(depth)} *featureType #{path}" 
      puts "#{pad(depth+1)} +title->#{REXML::XPath.first( node, '/featureType/title').text}"
      puts "#{pad(depth+1)} +enabled->#{REXML::XPath.first( node, '/featureType/enabled').text}"


    elsif REXML::XPath.first( node, "/namespace" )
      puts "#{pad(depth)} *namespace #{path}" 
      puts "#{pad(depth+1)} +prefix->#{REXML::XPath.first( node, '/namespace/prefix').text}"


    elsif REXML::XPath.first( node, "/dataStore" )
      puts "#{pad(depth)} *dataStore #{path}" 
      puts "#{pad(depth+1)} +name->#{REXML::XPath.first( node, '/dataStore/name').text}"

      type = REXML::XPath.first( node, '/dataStore/type') 
      if type
        puts "#{pad(depth+1)} +type->#{type.text}"
      end

      # a dataStore with a reference to a shapefile or other geometry
      url = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='url']" )
      if url
        print "#{pad(depth+1)} +url #{url.text} "
        x = url.text.scan( /file:(.*)/ ) 
        if not x.empty? 
          fullpath = "#{options[:dir]}/#{x.first().first() }"
          if File.exists?( fullpath)
              print " (OK)" 
              print " #{File.size(fullpath)}" 
          else
              abort( 'aborting')
          end
        end
        puts ""
      end

      jndi = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='jndiReferenceName']") 
      if jndi
        puts "#{pad(depth+1)} +jndi #{jndi.text} "
      end

      schema = REXML::XPath.first( node, "/dataStore/connectionParameters/entry[@key='schema']") 
      if schema
        puts "#{pad(depth+1)} +schema #{schema.text} "
      end


    elsif REXML::XPath.first( node, "/style" )
      puts "#{pad(depth)} *style #{path}" 
      puts "#{pad(depth+1)} +name->#{REXML::XPath.first( node, '/style/name').text}"

      # if it's a style with a ref to a stylefile 
      style_file = REXML::XPath.first( node, "/style/filename" )

      if style_file
        fullpath = "#{File.dirname( object[:path] )}/#{style_file.text}"
        print "#{pad(depth + 1)} +STYLEFILE #{fullpath}" 
        if File.exists?( fullpath)
            print " (OK)" 
            print " #{File.size(fullpath)}" 
        else
            abort( 'aborting')
        end
        puts
      end
    

    elsif REXML::XPath.first( node, "/workspace" )
      puts "#{pad(depth)} *workspace #{path}" 
      puts "#{pad(depth+1)} +name->#{REXML::XPath.first( node, '/workspace/name').text}"


    elsif REXML::XPath.first( node, "/coverage" )
      puts "#{pad(depth)} *coverage #{path}" 
      puts "#{pad(depth+1)} +name->#{REXML::XPath.first( node, '/coverage/name').text}"


    elsif REXML::XPath.first( node, "/coverageStore" )
      puts "#{pad(depth)} *coverageStore #{path}" 
      puts "#{pad(depth+1)} +name->#{REXML::XPath.first( node, '/coverageStore/name').text}"

      url = REXML::XPath.first( node, "/coverageStore/url" )
      if url
        print "#{pad(depth+1)} +url #{url.text} "
        x = url.text.scan( /file:(.*)/ ) 
        if not x.empty? 
          fullpath = "#{options[:dir]}/#{x.first().first() }"
          if File.exists?( fullpath)
              print " (OK)" 
          else
              abort( 'aborting')
          end
        end
        puts ""
      end

    else 
        puts "#{pad(depth+1)} +UNKNOWN element #{path}"
        abort( 'aborting' )
    end


    # call our block to perform the processing
    #yield object, depth
    # block.call object, depth 

    # find the sub objects this doc refers to
    # and process them
    REXML::XPath.each( object[:doc], "/*/*/id" ) do |e|
      trace_oid( oids, e.text , depth + 1, options )
    end


  end
end


### would it make sense to return the list of objects
### we are interested in scanning from rather than
### everything.

def begin_trace_from_layer_info( oids, options )

  # start tracing from the layer root keys
  oids.keys.each() do |oid|
    next unless ( oid =~ /LayerInfoImpl.*/ )
    trace_oid( oids, oid, 0, options )
  end
end


def trace_specific_layer( oids, name, options )

  # loop all keys 
  oids.keys.each() do |oid|
    next unless ( oid =~ /LayerInfoImpl.*/ )
    # loop all objects associated with each key
    oids[ oid].each() do |object|
      # try to extract a layername
      layer_name = REXML::XPath.first( object[:doc], "/layer/name" )
      # puts "layer name -> '#{layer_name.text}',  name ->  '#{name}'"

      if layer_name && layer_name.text == name
        # got a match, so use recusive scan
        puts "found match for '#{layer_name.text}'!"
        trace_oid( oids, oid, 0, options )
      end
    end
  end
end





### alright we should be passing the formatting or operation that we
### want to perform into the recursion.


require 'optparse'

options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"
  opts.on('-s', '--directory NAME', 'Geoserver config directory to scan') { |v| options[:dir] = v }
  opts.on('-l', '--layer NAME', 'dump specific layer name') { |v| options[:layer] = v }
end.parse!

if options[:layer]
  puts "looking for layer '#{options[:layer]}'" 
  trace_specific_layer( create_oid_mappings( options[:dir] ), options[:layer], options) 
else
  begin_trace_from_layer_info( create_oid_mappings( options[:dir] ), options ) 
end


puts ""

