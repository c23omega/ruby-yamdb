Yet another MDB Library

A Library for accessing Microsoft Access Database-Files with JET-Engine 4.0 written in pure ruby. It is based on brianb's mdbtools and its Hacking-Guide. Refer to https://github.com/brianb/mdbtools for additional Info. Some Features are extended, especially writing-Routines

Rubygem 'hex_string' is required for moving some strings into their hex representation.

What is working?
-> Reading Data-Tables
-> Writing Data-Tables with indiced Data

What is not working?
-> Updating and Deleting Rows
-> Not all Data-Types are supported, some rare used Types have to be implemented, take a Look at lib/row.rb.

Examples:

Reading:
db = Mdb::DBFile.new("mydb.mdb")
db.tables # List Tables
table = db.get_table("myTable")
row = table.fetch_row
puts row["myColumn"]
db.close

Writing:
db = Mdb::DBFile.new("mydb.mdb", true) # Last flag is writable
table = db.get_table("myTable")
table.insert_row("Col1Val", "Col2Val", ...)
db.close
