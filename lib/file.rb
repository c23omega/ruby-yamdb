module Mdb
  
  class DBFile
    
    attr_accessor :debug, :catalog
    
    include Helpers
    
    # Table catalog
    CatalogEntry = Struct.new(:name, :type, :page, :flags, :id) {
      def to_s
        puts "Catalog-Entry for Table #{name}, type: #{type} on Page #{page}, ID: #{id}"
      end
    }
    
    # Class variables:
    # @fd: File descriptor
    # @pagecount: Number of Pages in File
    # @catalog: List of CatalogEntries
    
    def initialize(file = nil, writable = false)
      @debug = false
      @pages = {}
      unless file.nil?
        open(file, writable)
      end
    end
    
    def open(file, writable = false)
      @fd = File.open(file, writable ? 'r+b' : 'rb')
      raise EOFError, "File length is not Consistent - Contains #{File.stat(file).size} \
Bytes - #{File.stat(file).size/(1024*4)} Pages, #{File.stat(file).size%(1024*4)} Bytes too much" if File.stat(file).size%(4*1024) != 0
      @pagecount = File.stat(file).size/(4*1024)
      
      read_catalog
    end
    
    def close
      @fd.close
    end
    
    def read_catalog
      objects_table = Table.new(self, 2, nil, @debug)
      @catalog = []
      row = objects_table.fetch_row
      while row
        entry = CatalogEntry.new
        entry.name = row["Name"]
        entry.type = row["Type"]
        entry.id = row["Id"]
        entry.page = row["Id"] & 0x00FFFFFF
        entry.flags = row["Flags"]
        @catalog << entry
        row = objects_table.fetch_row
      end
      @catalog
    end
    
    def tables
      @catalog.map {|c| c.name }
    end
    
    def get_page(num)
      # Use @pages for caching pages.
      # Do not create a pointer every time cause when data on the same
      # page is changed with two pointers, the pages differ and overwrite
      # themselves.
      return @pages[num] unless @pages[num].nil?
      @fd.seek(num*1024*4)
      pg = Page.new(MdbBinary.new(@fd.read(1024*4)), num)
      @pages[num] = pg
      return pg
    end
    
    def page_count
      @fd.size/(1024*4)
    end
    
    def get_table(name)
      @catalog.each {|c|
        return Table.new(self, c.page, c.name, @debug) if c.name == name
      }
      false
    end
    
    # Interesting for Investigating Mdb Files
    def get_table_by_pg(pg)
      @catalog.each {|c|
        return Table.new(self, pg, c.name, @debug) if c.page == pg
      }
      false
    end
    
    def new_data_page(table)
      pg = Page.new
      pg.number = @fd.size/(1024*4)
      pg.content = [1, 1, 1024*4-14, table.tdef_pg_num, 0, 0].pack("ccs<l<l<s<") # 14: Header-Länge
      pg.content.length.upto(1024*4-1) { pg.content += [0].pack("c") }
      pg.content = MdbBinary.new(pg.content)
      puts "Page length 1: #{pg.content.length}"
      save_page(pg) # Increment File size
      pg
    end
    
    def save_page(page)
      raise RuntimeError, "Page-Length of Page #{page.content.number} does not match #{1024*4}: #{page.content.length%(1024*4)}" if page.content.length%(1024*4) != 0
      @fd.seek(page.number*1024*4)
      @fd.write(page.content)
      @fd.flush
    end
    
  end
  
end