module Mdb
  
  class NoDefinitionTable < RuntimeError; end
  class WriteError < RuntimeError; end
  
  class Table
    
    include Helpers
    
    # Debug (output) variables?
    attr_accessor :debug
    attr_reader :num_rows, :file
    
    # Class Variables
    # @debug Output debug variables
    # @name Name of the Table
    # @file Datei
    # @tdef_pg: Table definition page
    # @columns: Columns of the Table
    # @num_rows Nunber of Rows in Table
    #
    # @cur_page
    # @cur_row Current row number
    
    def initialize(file, tdef_pg_num, name, debug = false)
      @debug = debug
      @name = name
      @file = file
      @indices = []
      
      tdef_pg = file.get_page(tdef_pg_num)
      
      # Be sure that the Page is a Table-Definition-Page
      raise NoDefinitionTable, "Page #{tdef_pg_num} is no valid Page definition for Table #{name} - Its Page-Type is #{tdef_pg.type} (#{tdef_pg.content.to_i8(0)})" if tdef_pg.content.to_i8(0) != 2
      @tdef_pg = tdef_pg
      
      @num_rows = tdef_pg.content.to_i32(16)
      
      # Read Columns
      @num_var_cols = tdef_pg.content.to_i16(43)
      num_cols = tdef_pg.content.to_i16(45)
      # Real indices - relevant for offset of columns
      real_idx = tdef_pg.content.to_i32(51)
      
      num_idx = tdef_pg.content.to_i32(47)
      puts "num_idx: #{num_idx}, real_idx: #{real_idx}" if @debug
      real_idx.times {|t|
        ind = Index.new("real", @file, @debug)
        ind.table = self
        @indices << ind
        puts "real_index #{t}: #{tdef_pg.content[(63+t*12)..(63+(t+1)*12-1)].to_hex_string} \
num_rows: #{tdef_pg.content.to_uint32(63+t*12+4)}" if @debug
        ind.count = tdef_pg.content.to_uint32(63+t*12+4)
      }
      
      column_offset = 63+12*real_idx
      @columns = []
      num_cols.times {
        col = Column.new
        col.type = tdef_pg.content.to_i8(column_offset)
        col.col_num = tdef_pg.content.to_i8(column_offset+5)
        col.var_col_num = tdef_pg.content.to_i16(column_offset+7)
        col.row_col_num = tdef_pg.content.to_i16(column_offset+9)
        if col.type == 16 # Numeric
          col.prec = tdef_pg.content.to_i8(column_offset+11)
          col.scale = tdef_pg.content.to_i8(column_offset+12)
        end
        col.fixed_offset = tdef_pg.content.to_i16(column_offset+21)
        #debugger if col.type <= 1
        col.size = tdef_pg.content.to_i16(column_offset+23) # if col.type > 1
        col.is_fixed = ((tdef_pg.content.to_i8(column_offset+15) & 1) > 0 ? true : false)
        column_offset += 25
        @columns << col
      }
      @columns.each {|col|
        len = tdef_pg.content.to_i16(column_offset)
        col.name = tdef_pg.content.to_ascii(column_offset+2, len)
        column_offset += (len + 2)
      }
      @columns = @columns.sort
      
      real_idx.times {|t|
        #puts "real_idx-Eintrag #{t} bei Offset #{column_offset} (#{[column_offset].pack("L<").to_hex_string})"
        index_cols = []
        10.times {|u|
          break if tdef_pg.content[(column_offset+u*(4+3+8+2+8)+4)..(column_offset+u*(4+3+8+2+8)+4+1)].to_hex_string == "ff ff"
          index_cols << tdef_pg.content.to_uint16(column_offset+4+u*(4+3+8+2+8))
        }
        @indices[t].usage_map = _read_bitmap(tdef_pg.content.to_i32(column_offset+34))
        @indices[t].column = @columns.select {|c| c.col_num == tdef_pg.content.to_uint16(column_offset+4) }[0] # First Column should be valid
        unless @indices[t].first_page = tdef_pg.content.to_uint32(column_offset+30+8)
          puts "Unable to read Index-Page for Table #{name}: #{tdef_pg.content.to_uint32(column_offset+30+8)}"
        end
        puts "Column-IDs for Index #{t}: #{index_cols.join(" ")} Erste Index-Page: #{tdef_pg.content[(column_offset+30+8)..(column_offset+30+11)].to_hex_string} Flags: #{tdef_pg.content[(column_offset+30+12)..(column_offset+30+13)].to_hex_string} Spalte: #{@indices[t].column.name}" if @debug
        #puts "Index-Page: #{tdef_pg.content[(column_offset+30+8)].to_hex_string} - #{tdef_pg.content.to_uint8(column_offset+30+8)}"
        column_offset += (30 + 4*5+2)
      }
      @real_index_number = @indices.length
      num_idx.times {|t|
        #puts "num_idx-Eintrag #{t} bei Offset #{column_offset} (#{[column_offset].pack("L<").to_hex_string})"
        puts "Index Number #{tdef_pg.content.to_uint32(column_offset+4)}, Index in Index Cols list: #{tdef_pg.content.to_uint32(column_offset+8)}, rel_tbl_type: #{tdef_pg.content[column_offset+12].to_hex_string} \
rel_idx_num: #{tdef_pg.content.to_i32(column_offset+13)}, rel_tbl_page #{tdef_pg.content.to_i32(column_offset+17)}, type: #{tdef_pg.content.to_uint8(column_offset+23)}" if @debug
        ind = Index.new("real", @file, @debug)
        ind.associated = @indices[tdef_pg.content.to_uint32(column_offset+8)]
        @indices << ind
        column_offset += 28
      }
      num_idx.times {|t|
        #puts "num_idx-Namenseintrag #{t} bei Offset #{column_offset} (#{[column_offset].pack("L<").to_hex_string})"
        len = tdef_pg.content.to_uint16(column_offset)
        puts "Name fuer Index #{t}: (len #{len}) #{tdef_pg.content.to_ascii(column_offset+2, len)}" if @debug
        @indices[@real_index_number+t].name = tdef_pg.content.to_ascii(column_offset+2, len)
        column_offset += (len + 2)
      }
      
      @usage_map = _read_bitmap(tdef_pg.content.to_i32(55))
      @free_map = _read_bitmap(tdef_pg.content.to_i32(59))
      
      @cur_page = read_next_pg(nil, @usage_map)
    end
    
    def indices
      @indices
    end
    
    # Getters
    def name
      @name
    end
    
    def columns
      @columns
    end
    
    def tdef_pg_num
      @tdef_pg.number
    end
    
    def row_count
      @num_rows
    end
    
    def fetch_row
      if !@cur_page
        puts "The requested Table contains no Columns."
        return false
      end
      puts "Fetching Row of Table #{@name}" if @debug
      return false if @cur_page == false # Actual Page has no more Records
      rows = @cur_page.content.to_uint16(12)
      if @cur_row >= rows
        @cur_page = read_next_pg(@cur_page, @usage_map)
        puts "Read next Page from Usage-Map: Page #{@cur_page.number}" if @debug && @cur_page
        return false unless @cur_page
      end
      start, size = _find_row(@cur_row, @cur_page)
      while (start & 0x4000) > 0 # Delflag - Row deleted
        puts "Row deleted. Looking for next Row." if @debug
        @cur_row += 1
        return fetch_row
      end
      @cur_row += 1
      puts "Found row #{@cur_row-1} on Page #{@cur_page.number} at Start #{start} with length #{size}" if @debug
      start = start & 0x1fff # Remove all flags
      Row.from_bits(self, MdbBinary.new(@cur_page.content[start..(start+size-1)]), @debug)
    end
    
    def insert_row(values)
      puts "Inserting into Table #{name}" if @debug
      row = Row.from_list(self, values, @debug)
      pg = read_next_pg(nil, @free_map)
      # Be Careful: What if on the found free page is not enough space?
      # And: Map Creation fails!
      unless pg
        puts "No Page on free Page found on Usage-Map. Creating one." if @debug
        pg = @file.new_data_page(self)
        # Save usage map
        puts "Recreating Usage and Free map" if @debug
        @usage_map = _read_bitmap(@tdef_pg.content.to_i32(55))
        add_page_to_map(pg, @usage_map)
        @free_map = _read_bitmap(@tdef_pg.content.to_i32(59))
        add_page_to_map(pg, @free_map)
      end
      puts "Writing on Data-Page #{pg.number} - Table definition Page #{@tdef_pg.number}" if @debug
      existing_rows = pg.content.to_uint16(12)
      # Increment num_rows
      pg.content[12..13] = [existing_rows+1].pack("S<")
      
      # Increment num_rows on tdef_pg
      @num_rows += 1
      puts "Wrote #{@num_rows} Columns"
      @tdef_pg.content[16..19] = [@num_rows].pack("l<")
      
      _real_indices.each_with_index {|index, i|
        # AAAAAAA!!!!!
        #puts "Skipping Index-Creation of Column #{index.column.name}" if ["Modified"].include?(index.column.name)
        #next if ["Modified"].include?(index.column.name)
        index.count += 1
        index.add_index(row[index.column.name], pg, existing_rows) # data, page, row
        @tdef_pg.content[(63+i*12)..(63+i*12+11)] = [@num_rows, index.count, 0].pack("L<L<L<")
        index.save
      }
      
      @file.save_page(@tdef_pg)
      
      # Where do we place the row?
      row_bytes = row.generate_bitstream
      last_row_start = existing_rows > 0 ? pg.content.to_uint16(14+(existing_rows-1)*2) : 1024*4
      raise IndexError, "On Page to write on is not enough Space. Implement to use an other page!" if (last_row_start - row_bytes.length) < (14+2*existing_rows+1)
      pg.content[(14+2*existing_rows)..(14+2*existing_rows+1)] = [last_row_start - row_bytes.length].pack("S<")
      pg.content[(last_row_start-row_bytes.length)..(last_row_start-1)] = row_bytes
      #pg.content[2..3] = [last_row_start-row_bytes.length].pack("S<")
      pg.content[2..3] = [pg.content.to_uint16(2)-row_bytes.length-2].pack("S<") # -2 wegen Header-Offset-Eintrag
      @file.save_page(pg)
      
    end
    
    # Internal functions
    def _find_page_row(page_row)
      pg = @file.get_page(page_row >> 8)
      [pg] + _find_row(page_row & 0xff, pg)
    end
    
    def _find_row(row, page)
      row_count = page.content.to_uint16(12)
      raise IndexError, "Invalid row number" if row_count < row
      start = page.content.to_uint16(14+2*row)
      next_start = (row == 0 ? 1024*4 : page.content.to_uint16(14+(row-1)*2)) & 0x1fff # Remove flags
      size = next_start - (start & 0x1fff)
      [start, size]
    end
    
    def _read_bitmap(page_row)
      page, start, length = _find_page_row(page_row)
      map = Bitmap.new(page, start, length)
      map
    end
    
    def add_page_to_map(page, map)
      current_usage_byte = map.content.to_uint8(page.number/8+5)
      #puts "Adding Page #{page.number} to map"
      #puts "Old usage map: #{map.content.to_hex_string}"
      new_byte = [current_usage_byte|(1 << (page.number%8))].pack("C")
      map.page.content[map.start + page.number/8+5] = new_byte
      #puts "New usage map: #{map.content.to_hex_string}"
      @file.save_page(map.page)
    end
    
    def _real_indices
      @indices[0..(@real_index_number-1)]
    end
    
  end
  
end