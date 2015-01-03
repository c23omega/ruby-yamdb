module Mdb
  
  class Row
    
    # Class variables:
    # @table Table of the row
    # @fields Fields of the row
    
    # @debug put debugging information?
    
    Field = Struct.new(:column, :value) do
      def length
        return column.size if column.is_fixed
        return value.length unless value.nil?
      end
    end
    
    def initialize(table, debug)
      @table = table
      @fields = []
      @debug = debug
    end
    
    def Row.from_bits(table, bits, debug)
      row = Row.new(table, debug)
      row.split_cols(bits)
      row
    end
    
    def Row.from_list(table, list, debug)
      row = Row.new(table, debug)
      raise IndexError, "List lengh does not match Column length" if table.columns.length != list.length
      list.each {|i| row.add_value(i) }
      row
    end
    
    def split_cols(bits)
      column_count = bits.to_uint16(0)
      # Nullmask contains a bitmask for null fields
      nullmask_size = (column_count+7)/8
      nullmask = bits[(bits.length-nullmask_size)..(bits.length-1)]
      
      var_col_offsets = calc_var_col_offsets(bits, nullmask)
      #debugstr = "Working line with #{bits.to_hex_string} (length #{bits.length}), Nullmask-length: #{nullmask_size}\n"
      debugstr = ""
      
      fixed_cols_found = 0
      fixed_col_count = column_count - var_col_offsets.length+1 # var_col_offsets.length is one element too large
      puts "Column Count Warning: Table columns: #{@table.columns.length} vs. #{column_count} columns" if @table.columns.length != column_count
      #puts "fixed: #{fixed_col_count}, var: #{var_col_offsets.length}"
      @table.columns.each {|col|
        f = Field.new
        f.column = col
        debugstr += "Column #{col.name} with type #{col.type} "
        
        # Check if Field is null
        byte_num = col.col_num / 8
        bit_num = col.col_num % 8
        if (nullmask[byte_num].unpack("C")[0] & (1 << bit_num)) == 0
          f.value = nil
          debugstr += "is null\n" 
          @fields << f
          next
        end
        
        if col.is_fixed && fixed_cols_found < fixed_col_count
          f.value = get_field_value(col, MdbBinary.new(bits[(col.fixed_offset+2)..(col.fixed_offset+col.size+1)]))
          fixed_cols_found += 1
          debugstr += "is fixed with length #{col.size}. Start: #{col.fixed_offset+2} Value: #{f.value}"
        elsif !col.is_fixed && col.var_col_num < var_col_offsets.length
          start = var_col_offsets[col.var_col_num]
          size = var_col_offsets[col.var_col_num+1]-start
          f.value = get_field_value(col, MdbBinary.new(bits[start..(start+size-1)]))
          debugstr += "is variable with length #{size}. Start: #{start} Value: #{[2, 9, 11].include?(f.column.type) ? f.value.to_hex_string : f.value}"
        else
          raise NoMethodError, "Field seems not to be set?"
        end
        debugstr += "\n"
        @fields << f
      }
      puts debugstr if @debug
    end
    
    def add_value(value)
      f = Field.new
      f.column = @table.columns[@fields.length]
      f.value = value
      @fields << f
    end
    
    def calc_var_col_offsets(bits, nullmask)
      var_col_offsets = []
      if @table.columns.select {|c| c.is_fixed == false }.length > 0
        var_cols_in_row = bits.to_uint16(bits.length-nullmask.length-2)
        (var_cols_in_row+1).times {|i|
          var_col_offsets << bits.to_uint16(bits.length-nullmask.length-4-(i*2))
        }
      end
      var_col_offsets
    end
    
    #
    # Getter-Functions for Fields
    #
    def get_field_value(col, bits)
      puts "Bits for Field #{col.name}: #{bits.to_hex_string}" if @debug
      case col.type
      when 1 then puts "Type Boolean in Column #{col.name} checked. Bits: #{bits.to_hex_string}"
      when 2 then puts "Type Byte in Column #{col.name} unhandled."
      when 3 then bits.to_uint16(0)                         # Int
      when 4 then bits.to_i32(0)                         # Longint
      when 5 then puts "Type Money in Column #{col.name} unhandled."
      when 6 then puts "Type Float in Column #{col.name} unhandled."
      when 7 then bits.to_f64(0)                            # Double
      when 8 then _get_datetime(bits)                       # Datetime
      when 9 then bits                                      # Binary
      when 10 then bits.to_ascii(0, bits.length)            # Text
      when 11 then _get_ole(col, bits)                      # OLE
      when 12 then _get_memo(col, bits)                     # Memo
      when 13 then puts "Type 13 in Column #{col.name} unhandled."
      when 14 then puts "Type 14 in Column #{col.name} unhandled."
      when 15 then puts "Type Repid in Column #{col.name} unhandled."
      when 16 then _get_numeric(col, bits)                  # Numeric
      when 18 then puts "Type Complex in Column #{col.name} unhandled."
      end
    end
    
    def _get_datetime(bits)
      d = bits.to_f64(0)
      day = d.to_i
      time = (d-day).abs.to_i*86400.0+0.5
      days_since_epoch = day-(1970-1899)*365
      sec_since_epoch = days_since_epoch*24*3600+time
      Time.at(sec_since_epoch).to_datetime
    end
    
    def _get_ole(col, bits)
      if bits.length < 12
        return nil
      end
      
      val = _get_page_bits(col, bits)
      val
    end
    
    def _get_memo(col, bits)
      if bits.length < 12
        return nil
      end
      
      val_bits = _get_page_bits(col, bits)
      if val_bits.nil? 
        return nil
      end
      val_bits.to_ascii(0, val_bits.length) unless val_bits.nil?
    end
    
    def _get_numeric(col, bits)
      multiplier = Array.new(28, 0)
      multiplier[0] = 1
      tmp = []
      num = bits[0].unpack("C")[0] & 0x80 > 0 ? "-" : ""
      newval = Array.new(28, 0)
      bytes = bits[1..16]
      16.times {|t| # f.size.times ?! # 2 vs 16
        newval, multiplier = _multiply_byte(newval, bytes[12-4*(t/4)+t%4].unpack("C")[0], multiplier)
        tmp = multiplier.select { true }
        multiplier = multiplier.map { 0 }
        multiplier, tmp = _multiply_byte(multiplier, 256, tmp)
      }
      top = 28
      while ((top > 0) && (top-1 > col.scale) && (newval[top-1] == 0))
        top-=1
      end
      if top == 0
        num += "0"
      else
        i = top
        while (i > 0)
          num += "." if (i == col.scale)
          num += newval[i-1].to_s
          i-= 1
        end
      end
      num.to_f
    end
    
    def _multiply_byte(product, num, multiplier)
      number = []
      number[0] = num%10
      number[1] = (num/10)%10
      number[2] = (num/100)%10
      28.times {|t|
        next if multiplier[t] == 0
        3.times {|u|
          next if number[u] == 0
          product[t+u] = multiplier[t]*number[u]
        }
        27.times {|u|
          if product[u].to_i > 9
            product[u+1] += product[u]/10
            product[u] = product[u]%10
          end
        }
        product[27] = product[27]%10 if product[27] > 9
      }
      return product, multiplier
    end
    
    def _get_page_bits(col, bits)
      len = bits.to_i32(0)
      if (len & 0x80000000) > 0
        MdbBinary.new(bits[12..(bits.length-1)])
      elsif (len & 0x40000000) > 0
        pg_row = bits.to_i32(4)
        pg, start, size = @table._find_page_row(pg_row)
        MdbBinary.new(pg.content[(start & 0x1fff)..((start & 0x1fff)+size-1)])
      else
        pg_row = bits.to_i32(4)
        pg, start, size = @table._find_page_row(pg_row)
        content = MdbBinary.new(pg.content[((start & 0x1fff)+4)..((start & 0x1fff)+size-1)])
        pg_row = pg.content.to_i32(start & 0x1fff)
        while (pg_row != 0)
          pg, start, size = @table._find_page_row(pg_row)
          content += pg.content[(start & 0x1fff+4)..((start & 0x1fff)+size-1)]
          pg_row = pg.content.to_i32(start & 0x1fff)
        end
        content
      end
    end
    
    #
    # Bitstream-Generation-Functions for Fields
    #
    def generate_bitstream
      # 1.: Field count
      buf = [@fields.length].pack("S<")
      # 2.: Set fixed Cols
      @fields.each {|f|
        next unless f.column.is_fixed
        puts "Field for Col #{f.column.name} from #{(f.column.fixed_offset+2)} to #{(f.column.fixed_offset+f.length+2)}"
        buf += [0].pack("C") while buf.length < (f.column.fixed_offset+2)
        buf[(f.column.fixed_offset+2)..(f.column.fixed_offset+f.length+1)] = get_bit_value(f) unless f.value.nil?
      }
      # Any var cols present?
      num_var_cols = @table.columns.select{|c| c.is_fixed == false }.length
      if num_var_cols == 0
        buf += [buf.length].pack("S<") # Length of Data
        buf += [0].pack("S<") # 0 var_cols
        return buf + generate_nullmask
      end
      #buf += [0].pack("L<")
      var_starts = []
      @fields.each {|f|
        next if f.column.is_fixed
        var_starts << buf.length
        buf += get_bit_value(f) unless f.value.nil?
      }
      buf += [buf.length].pack("S<") # EOD - Length of data - including 2 bytes at the beginning (num_cols)?
      var_starts.reverse.each {|start|
        buf += [start].pack("S<")
      }
      buf += [var_starts.length].pack("S<")
      buf + generate_nullmask
    end
    
    def generate_nullmask
      byte = bit = 0
      buf = ""
      @fields.each {|f|
        # col is null if bit is 0
        byte |= (1 << bit) unless f.value.nil?
        bit += 1
        if (bit == 8)
          buf += [byte].pack("C")
          bit = byte = 0
        end
      }
      buf += [byte].pack("C") if (bit > 0)
      buf
    end
    
    def get_bit_value(field)
      bits = case field.column.type
      when 1 then puts "Insert-Type Boolean in Column #{field.column.name} unhandled."
      when 2 then puts "Insert-Type Byte in Column #{field.column.name} unhandled."
      when 3 then [field.value].pack("s<")                         # Int
      when 4 then [field.value].pack("l<")                         # Longint
      when 5 then puts "Insert-Type Money in Column #{field.column.name} unhandled."
      when 6 then puts "Insert-Type Float in Column #{field.column.name} unhandled."
      when 7 then [field.value].pack("E")                          # Double
      when 8 then puts "Insert-Type Datetime in Column #{field.column.name} unhandled."
      when 9 then field.value                                      # Binary
      when 10 then Iconv.conv("UCS-2", "UTF-8", field.value)       # Text
      when 11 then _generate_ole(field.value)                      # OLE
      when 12 then _generate_memo(field.value)                     # Memo
      when 13 then puts "Insert-Type 13 in Column #{field.column.name} unhandled."
      when 14 then puts "Insert-Type 14 in Column #{field.column.name} unhandled."
      when 15 then puts "Insert-Type Repid in Column #{field.column.name} unhandled."
      when 16 then puts "Insert-Type Numeric in Column #{field.column.name} unhandled."
      when 18 then puts "Insert-Type Complex in Column #{field.column.name} unhandled."
      end
      puts "Bits for Field #{field.column.name} (type #{field.column.type_name}): #{bits.to_hex_string}" if @debug
      bits
    end
    
    def _generate_ole(value)
      # Method to write inline fields can not be read by Cameo for some reason
      #buf = [(value.length)|0x80000000].pack("l<")
      #buf += [0, 0].pack("l<l<")
      #buf + value
      pg = _generate_lval_page(value)
      [value.length|0x40000000, 0, pg.number, 0, 0].pack("L<CCS<L<")
    end
    
    def _generate_memo(value)
      # Method to write inline fields can not be read by Cameo for some reason
      #ucs2 = Iconv.conv("UCS-2", "UTF-8", value)
      #buf = [ucs2.length|0x80000000, 0, 0].pack("L<L<L<") # ucs2.length = 78, value.length = 39
      #buf + ucs2
      ucs2 = Iconv.conv("UCS-2", "UTF-8", value)
      pg = _generate_lval_page(ucs2)
      [ucs2.length|0x40000000, 0, pg.number, 0, 0].pack("L<CCS<L<")
    end
    
    def _generate_lval_page(value)
      raise WriteError, "Cannot write more than #{1024*4-12} Bytes." if value.length >= (1024*4-12)
      pg = @table.file.new_data_page(@table)
      pg.content[2..3] = [1024*4-value.length-16].pack("S<")
      pg.content[4..8] = [76, 86, 65, 76].pack("CCCC") # LVAL
      pg.content[12..13] = [1].pack("S<")
      pg.content[14..15] = [1024*4-value.length].pack("S<")
      pg.content[(1024*4-value.length)..(1024*4)] = value
      @table.file.save_page(pg)
      return pg
    end
    
    def [](index)
      return @fields[index].value if index.kind_of?(Integer)
      @fields.each {|f|
        return f.value if f.column.name == index
      }
      nil
    end
    
    def fields
      @fields
    end
    
    def to_s
      max = 0
      @fields.each {|f| max = f.column.name.length if max < f.column.name.length }
      @fields.map {|f| 
        if f.value.nil?
          "Null; "
        elsif [2, 9, 11].include?(f.column.type)
          "#{f.value.to_hex_string}; "
        else
          "#{f.value} (#{f.length}); "
        end
      }.join
    end
    
    def !=(other)
      return true unless other
      differs = false
      @fields.each_with_index {|f, i|
        differs = true if f.value != other.fields[i].value
      }
      differs
    end
    
  end
  
end