module Mdb
  
  DATA_MAP = {
    '0' => 54, '1' => 56, '2' => 58, '3' => 60, '4' => 62,
    '5' => 64, '6' => 66, '7' => 68, '8' => 70, '9' => 72,
    'a' => 74, 'b' => 76, 'c' => 77, 'd' => 79, 'e' => 81, 'f' => 83, 'g' => 85,
    'h' => 87, 'i' => 89, 'j' => 91, 'k' => 92, 'l' => 94, 'm' => 96, 'n' => 98,
    'o' => 100, 'p' => 102, 'q' => 104, 'r' => 105, 's' => 107, 't' => 109,
    'u' => 111, 'v' => 113, 'w' => 115, 'x' => 117, 'y' => 118, 'z' => 120,
    ' ' => 07
    }
  
  class Index
    
    include Helpers
    
    attr_accessor :table, :associated, :name, :column, :count
    attr_reader :type, :bitmask, :current
    
    def initialize(type, file, debug)
      @file = file
      @type = type
      @entry = 0
      @debug = debug
      @entries = []
    end
    
    def usage_map=(bitmap)
      @usage_map = bitmap
      #puts "Current Usage-Bitmask: #{@usage_map.content.to_hex_string}"
      usage_pg = read_next_pg(nil, @usage_map)
      while (usage_pg)
        #puts "Page: #{usage_pg.number}"
        usage_pg = read_next_pg(usage_pg, @usage_map)
      end
    end
    
    def first_page=(pg)
      @current = @file.get_page(pg)
      return false if @current.type != "Leaf Index Page"
      @bitmask = Bitmap.new(@current, 27, (480-27))
      read_page_entries
      true
    end
    
    def create
      # Do more ... Write Page-Header-Info usw.
      @bitmask = Bitmap.new # More!
    end
    
    def read_page_entries
      @entries = [480]
      
      start = 480
      mask_bit = 0
      mask_pos = 27
      while (mask_pos < 480)
        len = 0
        while (true)
          mask_bit += 1
          if mask_bit == 8
            mask_bit = 0
            mask_pos += 1
          end
          len += 1
          break if mask_pos == 480 || ((1 << mask_bit) & @current.content.to_uint8(mask_pos) > 0)
        end
        start += len
        @entries << start if mask_pos < 480
      end
    end
    
    def save
      @file.save_page(@current)
    end
    
    def get_entry
      return nil if @entries.length == @entry+1 || @entries.length == 0
      @entry += 1
      puts "Reading from #{@entries[@entry-1]} to #{@entries[@entry]} on Page #{@current.number}, Len: #{@entries[@entry]-@entries[@entry-1]}" if @debug
      @current.content[@entries[@entry-1]..(@entries[@entry]-1)].to_hex_string
    end
    
    def add_index(data, page, row)
      puts "Adding Index for Data #{data} (Column #{column.name}) to Page #{page.number}" if @debug
      if data.nil?
        bin = [0, 0, 0, page.number, row].pack("CCCCC")
      elsif @column.name == "Modified"
        bin = [127, 194].pack("CC")
        binary = [data].pack("E")
        binary = binary[0..(binary.length-2)]
        bin += binary.reverse
        bin += [0, 0, page.number, row].pack("CCCC")
      elsif @column.name == "Name"
        bin = [127].pack("C")
        data.length.times {|t| bin += [DATA_MAP[data[t].downcase]].pack("C") }
        bin += [1, 0, 0, 0, page.number, row].pack("CCCCCC")
      else
        bin = [127].pack("C") # 0x7f
        data = data.to_s.split("-").join
        #data.length.times {|t| puts "Translating #{data[t]} in #{DATA_MAP[data[t].downcase]}"}
        data.length.times {|t| bin += [DATA_MAP[data[t].downcase]].pack("C") }
        #puts "Bin 1: #{bin.to_hex_string}"
        add = [1, 1, 1, 1, 128, 39, 6, 130, 128, 55, 6, 130, 128, 71, 6, 130, 128, 87, 6, 130, 0, 0, 0, page.number, row]
        add.length.times {|t| bin += [add[t]].pack("C") }
      end
      puts "Index-Bits: #{bin.to_hex_string}"
      #puts "Bitmask: #{@current.content[27..449].to_hex_string}"
      #puts "Entries: #{@entries}"
      @entries << @entries.last+bin.length
      @current.content[@entries[@entries.length-2]..(@entries[@entries.length-1]-1)] = bin
      @current.content[2..3] = [@current.content[2..3].unpack("S<")[0] - bin.length].pack("S<")
      bit = (@entries.last-480)/8
      #puts "Bitmask: #{@bitmask.content.to_hex_string}"
      @bitmask[bit] = [@bitmask.content.to_uint8(bit) | (1 << ((@entries.last-480)%8))].pack("C")
      #puts "Writing to Bit #{bit} + start #{@bitmask.start} => #{bit + @bitmask.start}, Index-PG: #{@current.number}"
      #puts "Bitmask: #{@current.content[27..449].to_hex_string}"
      #puts "Bitmask: #{@bitmask.content.to_hex_string}"
      #puts "Entries: #{@entries}"
      # Possibly update not used space
      # What if we need an other Index-Page? - Page size not checked!
    end
    
  end
  
  class << self
    def test_indices
      f = Mdb::DBFile.new "/home/heinrich/edi/result_cm.mdb"
      f.debug = true
      l = ["ACAccounts", "ACAttach", "ACDefaultDefinitions",
"ACDefinitions", "ACGrants", "ACJoins", "ACObjectTypes", "ACRights",
"CheckOuts", "CommandActions", "EvalPredictionLists", "EvalResults",
"Evaluations", "EvalVariants", "GCBData", "IOSystems", "Projects", "TestLayouts",
"TestParamOPs", "TestParams", "TestResults", "Tests", "TestSequences", 
"TestSequenceTestParams", "TransmissionData", "UserMap", "Version", "XMLData"]
      l.each {|i|
        puts "Reading Table #{i}"
        t = f.get_table(i)
        puts "Tdef: #{t.tdef_pg_num} - #{[t.tdef_pg_num].pack("C").to_hex_string}"
        gets
      }
      #index = t.indices[6]
      #puts "Index name: #{index.name}"
      #puts "Hex entry: #{index.associated.get_entry}"
      nil
    end
    
    def test
      f = Mdb::DBFile.new "/home/heinrich/edi/result_cm.mdb"
      f.debug = false
      t = f.get_table("Projects")
      puts "Index-Names: #{t.indices.map {|i| i.name }}"
      t = f.get_table("GCBData")
      puts "Index-Names: #{t.indices.map {|i| i.name }}"
      t = f.get_table("IOSystems")
      puts "Index-Names: #{t.indices.map {|i| i.name }}"
      read("Projects", "/home/heinrich/edi/result_cm.mdb")
      read("IOSystems", "/home/heinrich/edi/result_cm.mdb")
      read("GCBData", "/home/heinrich/edi/result_cm.mdb")
      read("UserMap", "/home/heinrich/edi/result_cm.mdb")
      nil
    end
    
    def show_indices
      f = Mdb::DBFile.new "/home/heinrich/edi/result.mdb"
      ["Projects", "GCBData", "IOSystems"].each {|name|
        show_index(f.get_table(name))
      }
    end
    
    def show_index(t)
      puts " -"
        puts " --- Checking #{t.name} ---"
        puts " -"
        puts "tdef_pg: #{t.tdef_pg_num}"
        t.indices.each_with_index {|ind, i|
          if ind.name.nil?
            puts "Checking real Index #{i} for column #{ind.column.name}"
            entry = ind.get_entry
            while entry
              puts entry
              entry = ind.get_entry
            end
          else
            next if ind.name[0] == "."
            puts "Checking logical Index #{ind.name}. Associated with real index: #{t.indices.index(ind.associated)}"
          end
        }
    end
    
    def translate_index_string(str)
      puts str.split(" ").map {|i| DATA_MAP.invert[i.to_i(16)] }.join
      nil
    end
    
    def relations
      f = Mdb::DBFile.new "/home/heinrich/edi/result_cm.mdb"
      t = f.get_table("Relationships")
      row = t.fetch_row
      rows = []
      while (row)
        rows << row
        row = t.fetch_row
      end
      puts t.columns.map {|c| c.name }
      puts rows.select {|r| [86, 92, 103].include?(r[0].to_i) }.join("\n")
    end
    
    def test_db_indices
      f = Mdb::DBFile.new "/home/heinrich/edi/Datenbank2.mdb"
      t = f.get_table("Tabelle1")
      index = t.indices[1]
      puts "Index name: #{index.name}"
      puts "Hex entry: #{index.associated.get_entry}"
      nil
    end
  
  end
  
end