Yet another MDB Library

A Library for accessing Microsoft Access Database-Files with JET-Engine 4.0 written in pure ruby. It is based on brianb's mdbtools and its Hacking-Guide. Refer to https://github.com/brianb/mdbtools for additional Info. Differences to this toolset is it is pure ruby, some writing-Routines are extended but updating and deleting-Methods are not supported.

Rubygem 'hex_string' is required for moving some strings into their hex representation.

What is working?<br>
-> Reading Data-Tables<br>
-> Writing Data-Tables with indiced Data<br>

What is not working?<br>
-> Updating and Deleting Rows<br>
-> Not all Data-Types are supported, some rare used Types have to be implemented, take a Look at lib/row.rb.<br>

Examples:

Reading:
```ruby
db = Mdb::DBFile.new("mydb.mdb")
db.tables # List Tables
table = db.get_table("myTable")
row = table.fetch_row
puts row["myColumn"]
db.close
```

Writing:
```ruby
db = Mdb::DBFile.new("mydb.mdb", true) # Last flag is writable
table = db.get_table("myTable")
table.insert_row("Col1Val", "Col2Val", ...)
db.close
```
