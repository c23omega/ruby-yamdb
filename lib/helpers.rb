module Mdb
  
  module Helpers
    
    Page = Struct.new(:content, :number) do
      def type
        case content.to_i8(0)
        when 0 then "Database Definition page"
        when 1 then "Data page"
        when 2 then "Table definition page"
        when 3 then "Intermediate Index page"
        when 4 then "Leaf Index Page"
        when 5 then "Page Usage Bitmap (extended page usage)"
        end
      end
      
      def tdef_pg
        case type
        when 0 then "No Database Definition-Page available."
        when 1 then content[4..7] == "LVAL" ? "Long-Value Data Page" : content.to_uint32(4)
        when 2 then "Page is a Table definition page."
        when 3 then "?"
        when 4 then "?"
        when 5 then "?"
        end
      end
    end
    
    Column = Struct.new(:type, :col_num, :var_col_num, :row_col_num, :fixed_offset, :size, :name, :is_fixed, :prec, :scale) do
      include Comparable
      def print_content
        "Column #{name} Total num: #{col_num}, Type: #{type_name}, Var-Offset: #{var_col_num}, Fixed Offset: #{col_fixed_offset}, Size: #{size}"
      end
      
      def type_name
        case type
        when 1 then "Boolean"
        when 2 then "Byte"
        when 3 then "Int"
        when 4 then "Longint"
        when 5 then "Money"
        when 6 then "Float"
        when 7 then "Double"
        when 8 then "Datetime"
        when 9 then "Binary"
        when 10 then "Text"
        when 11 then "Ole"
        when 12 then "Memo"
        when 15 then "Repid"
        when 16 then "Numeric"
        when 18 then "Complex"
        end
      end
      
      def <=>(other)
        col_num <=> other.col_num
      end
    end
    
    Bitmap = Struct.new(:page, :start, :length) do
      def content
        MdbBinary.new(page.content[start..(start+length-1)])
      end
      
      def content=(new)
        page.content[start..(start+length-1)] = new
      end
      
      def []=(index, new)
        page.content[start+index] = new
      end
    end
    
    def read_next_pg(cur_page, map)
      @cur_row = 0
      raise NoMethodError if map.content[0].to_hex_string != "00"
      num = map.content.to_i32(1)
      usage_bitlen = (map.length-5)*8
      i = (!cur_page.nil? && cur_page.number >= num) ? cur_page.number-num+1 : 0
      pg = 0
      i.upto(usage_bitlen-1) {|t|
        if (map.content[t/8+5].unpack('C')[0] & (1 << (t%8))) > 0
          pg = num + t
          puts "Found next Page #{pg}" if @debug
          return @file.get_page(pg)
        end
      }
      false
    end
    
  end
  
  class MdbBinary < Binary
    
    def to_ascii(offset, len)
      
      str = @str[offset..(offset+len-1)]
        
      if str.length >= 2 && str[0].to_hex_string == 'ff' && str[1].to_hex_string == 'fe'
        compress = true
        tmp = ""
        done = 0
        while (str.length > done+2)
          if (str[done+2].unpack("C")[0] == 0)
            compress = (compress ? false : true)
            done += 1
          elsif compress
            tmp += str[done+2]
            tmp += [0].pack("C")
            done += 1
          elsif str.length-done >= 2
            tmp += str[done+2] + str[done+3]
            done += 2
          end
        end
        str = tmp
      end
      
      dest = ' '*(str.length/2)
      0..(str.length/2).times {|t|
        dest[t] = (str[t*2+1].unpack("C")[0] == 0 ? str[t*2] : '?')
      }
      dest
    end
  end
end