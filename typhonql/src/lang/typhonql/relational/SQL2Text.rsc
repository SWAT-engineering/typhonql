/********************************************************************************
* Copyright (c) 2018-2020 CWI & Swat.engineering 
*
* This program and the accompanying materials are made available under the
* terms of the Eclipse Public License 2.0 which is available at
* http://www.eclipse.org/legal/epl-2.0.
*
* This Source Code may also be made available under the following Secondary
* Licenses when the conditions for such availability set forth in the Eclipse
* Public License, v. 2.0 are satisfied: GNU General Public License, version 2
* with the GNU Classpath Exception which is
* available at https://www.gnu.org/software/classpath/license.html.
*
* SPDX-License-Identifier: EPL-2.0 OR GPL-2.0 WITH Classpath-exception-2.0
********************************************************************************/

module lang::typhonql::relational::SQL2Text

import lang::typhonql::relational::SQL;
import lang::typhonql::relational::Util;
import lang::typhonml::Util;
import lang::typhonql::util::Dates;
import lang::typhonql::util::UUID;
import List;
import String;
import DateTime;

// NB: we use ` to escape identifiers, however, this is not ANSI SQL, but works in MySQL
str q(str x) = "`<x>`";


str pp(list[SQLStat] stats) = intercalate("\n\n", [ pp(s) | SQLStat s <- stats ]);

str pp(map[Place,list[SQLStat]] placed)
  = intercalate("\n", [ "<p>: <pp(placed[p])>" | Place p <- placed ]); 

// SQLStat

str pp(create(str t, list[Column] cs, list[TableConstraint] cos))
  = "create table <q(t)> (
    '  <intercalate(",\n", [ pp(c) | Column c <- cs ] + [ pp(c) | TableConstraint c <- cos ])>
    ');";

//str pp(renameTable(str t, str newName))
//  = "rename table <q(t)> to <q(newName)>;";

str pp(\insert(str t, list[str] cs, list[SQLExpr] vs))
  = "insert into <q(t)> (<intercalate(", ", [ q(c) | str c <- cs ])>) 
    'values (<intercalate(", ", [ pp(v) | SQLExpr v <- vs ])>);";
  

str pp(update(str t, list[Set] ss, list[Clause] cs))
  = "update <q(t)> set <intercalate(", ", [ pp(s) | Set s <- ss ])>
    '<intercalate("\n", [ pp(c) | Clause c <- cs ])>;";
  
str pp(delete(str t, list[Clause] cs))
  = "delete from <q(t)> 
    '<intercalate("\n", [ pp(c) | Clause c <- cs ])>;";

str pp(deleteJoining(list[str] tables, list[Clause] cs)) 
  = "delete <intercalate(", ", [ q(t) | str t <- tables ])> 
    'from <intercalate(" inner join ", [ q(t) | str t <- tables ])>
    '<intercalate("\n", [ pp(c) | Clause c <- cs ])>";

str pp(select(list[SQLExpr] es, list[As] as, list[Clause] cs))
  =  "select <intercalate(", ", [ pp(e) | SQLExpr e <- es ])> 
    'from <intercalate(", ", [ pp(a) | As a <- as ])>
    '<intercalate("\n", [ pp(c) | Clause c <- cs ])>;";  

str pp(alterTable(str t, list[Alter] as))
  = "alter table <q(t)>
    '<intercalate(",\n", [ pp(a) | Alter a <- as ])>;";


str pp(dropTable(list[str] tables, bool ifExists, list[DropOption] options))
  = "drop table <ifExists ? "if exists " : ""><intercalate(", ", [ q(t) | str t <- tables])> <intercalate(", ", [ pp(opt) | DropOption opt <- options ])>;";

str pp(DropOption::restrict()) = "restrict";

str pp(DropOption::cascade()) = "cascade";

// Alter
str pp(addConstraint(c:index(_, _, _)))
  = "add 
    '<pp(c)>";
   
str pp(addConstraint(TableConstraint c))
  = "add constraint 
    '<pp(c)>"
  when index(_, _, _) !:= c;
    
str pp(dropConstraint(str name))
  = "drop constraint <q(name)>";
  
str pp(dropIndex(str name))
  = "drop index <q(name)>";  
    
str pp(addColumn(column(str name, ColumnType \type, list[ColumnConstraint] constraints)))
  = "add <q(name)> <pp(\type)>";

str pp(dropColumn(str name))
  = "drop column <q(name)>";
  

str pp(renameColumn(str name, str newName))
  = "rename column <q(name)> to <q(newName)>";  

str pp(renameTable(str name))
  = "rename to <q(name)>";

// As

str pp(as(str t, str x)) = "<q(t)> as <q(x)>";

str pp(leftOuterJoin(As left, As right, SQLExpr on))
  = "<pp(left)> left outer join <pp(right)> on <pp(on)>";

str pp(leftOuterJoin(As left, list[As] rights, list[SQLExpr] ons)) {
  str s = pp(left);
  for (int i <- [0..size(rights)]) {
    s += " left outer join <pp(rights[i])>";
    s += " on <pp(ons[i])>";
  }
  return s;
}
// Set

str pp(\set(str c, SQLExpr e)) = "<q(c)> = <pp(e)>";


// SQLExpr

str pp(column(str table, str name)) = "<q(table)>.<q(name)>";
str pp(named(SQLExpr e, str as)) = "<pp(e)> as <q(as)>";
str pp(lit(Value val)) = pp(val);
str pp(placeholder(name = str name)) =  name == "" ? "?" : "${<name>}";
str pp(not(SQLExpr arg)) = "not (<pp(arg)>)";
str pp(neg(SQLExpr arg)) = "-(<pp(arg)>)"; 
str pp(pos(SQLExpr arg)) = "+(<pp(arg)>)";
str pp(mul(SQLExpr lhs, SQLExpr rhs)) = "(<pp(lhs)>) * (<pp(rhs)>)"; 
str pp(div(SQLExpr lhs, SQLExpr rhs)) = "(<pp(lhs)>) / (<pp(rhs)>)"; 
str pp(add(SQLExpr lhs, SQLExpr rhs)) = "(<pp(lhs)>) + (<pp(rhs)>)"; 
str pp(sub(SQLExpr lhs, SQLExpr rhs)) = "(<pp(lhs)>) - (<pp(rhs)>)"; 
str pp(equ(SQLExpr lhs, SQLExpr rhs)) = "(<pp(lhs)>) = (<pp(rhs)>)"; 
str pp(neq(SQLExpr lhs, SQLExpr rhs)) = "(<pp(lhs)>) \<\> (<pp(rhs)>)"; 
str pp(leq(SQLExpr lhs, SQLExpr rhs)) = "(<pp(lhs)>) \<= (<pp(rhs)>)"; 
str pp(geq(SQLExpr lhs, SQLExpr rhs)) = "(<pp(lhs)>) \>= (<pp(rhs)>)"; 
str pp(lt(SQLExpr lhs, SQLExpr rhs)) = "(<pp(lhs)>) \< (<pp(rhs)>)"; 
str pp(gt(SQLExpr lhs, SQLExpr rhs)) = "(<pp(lhs)>) \> (<pp(rhs)>)"; 
str pp(like(SQLExpr lhs, SQLExpr rhs)) = "(<pp(lhs)>) like (<pp(rhs)>)"; 
str pp(or(SQLExpr lhs, SQLExpr rhs)) = "(<pp(lhs)>) or (<pp(rhs)>)"; 
str pp(and(SQLExpr lhs, SQLExpr rhs)) = "(<pp(lhs)>) and (<pp(rhs)>)";
str pp(notIn(SQLExpr arg, list[Value] vals)) 
  = "(<pp(arg)>) not in (<intercalate(", ", [ pp(v) | SQLExpr v <- vals])>)";
str pp(\in(SQLExpr arg, list[SQLExpr] vals)) 
  = "(<pp(arg)>) in (<intercalate(", ", [ pp(v) | SQLExpr v <- vals])>)";


str pp(distance(SQLExpr lhs, SQLExpr rhs)) 
    = "(
     6371000 * 2 * ASIN(SQRT(
       POWER(SIN((ST_Y(<pp(rhs)>) - ST_Y(<pp(lhs)>)) * pi()/180 / 2),
       2) + COS(ST_Y(<pp(lhs)>) * pi()/180 ) * COS(ST_Y(<pp(rhs)>) *
       pi()/180) * POWER(SIN((ST_X(<pp(rhs)>) - ST_X(<pp(lhs)>)) *
       pi()/180 / 2), 2) ))
    )";
str pp(var(str name))
  = "`<name>`";

str pp(fun(str name, vals)) = "<name>(<intercalate(", ", [pp(v) | v <- vals])>)";

str pp(SQLExpr::placeholder(name = str name)) = "${<name>}";

// Clause

str pp(where(list[SQLExpr] es)) = "where <intercalate(" and ", [ pp(e) | SQLExpr e <- es ])>"; 

str pp(groupBy(list[SQLExpr] es)) = "group by <intercalate(", ", [ pp(e) | SQLExpr e <- es ])>"; 

str pp(having(list[SQLExpr] es)) = "having <intercalate(", ", [ pp(e) | SQLExpr e <- es ])>"; 

str pp(orderBy(list[SQLExpr] es, Dir d)) = "order by <intercalate(", ", [ pp(e) | SQLExpr e <- es ])> <pp(d)>"; 

str pp(limit(SQLExpr e)) = "limit <pp(e)>"; 
str pp(offset(SQLExpr e)) = "offset <pp(e)>"; 

// Dir

str pp(asc()) = "asc";

str pp(desc()) = "desc";


// Column
    
str pp(column(str c, ColumnType t, list[ColumnConstraint] cos))
  = "<q(c)> <intercalate(" ", [pp(t)] + [ pp(co) | ColumnConstraint co <- cos ])>";
  

// Value

map[str, str] escapes = (
    "\'": "\\\'",
    "\"": "\\\"",
    "\b": "\\b",
    "\n": "\\n",
    "\r": "\\r",
    "\t": "\\t",
    "\a26": "\\z",
    "\\": "\\\\",
    "%": "\\%",
    "_": "\\_"
);

str pp(text(str x)) = "\'" + escape(x, escapes) + "\'";

str pp(decimal(real x)) = "<x>";

str pp(integer(int x)) = "<x>";

str pp(boolean(bool b)) = "<b>";

str pp(dateTime(datetime d)) = "\'<printUTCDateTime(d, "YYYY-MM-dd HH:mm:ss")>\'";

str pp(date(datetime d)) = "\'<printDate(d, "YYYY-MM-dd")>\'";

str pp(point(real x, real y)) = "PointFromText(\'POINT(<x> <y>)\', 4326)";

str pp(polygon(list[lrel[real, real]] segs)) 
  = "PolyFromText(\'POLYGON(<intercalate(", ", [ seg2str(s) | s <- segs ])>)\', 4326)";

str seg2str(lrel[real,real] seg)  
  = "(<intercalate(", ", [ "<x> <y>" | <real x, real y> <- seg ])>)";

str pp(null()) = "null";

str pp(Value::placeholder(name = str name)) = "${<name>}";

str pp(blobPointer(str pointer)) = "${blob-<pointer>}";

str pp(sUuid(str uuid)) = "unhex(\'<replaceAll("<uuid>", "-", "")>\')";

// TableConstraint

str pp(primaryKey(str c)) = "primary key (<q(c)>)";

str pp(foreignKey(str c, str p, str k, OnDelete od)) 
  = "foreign key `fk-<makeUUID()>` (<q(c)>) 
    '  references <q(p)>(<q(k)>)<pp(od)>";


str pp(index(_, spatial(), list[str] columns))
    = intercalate(", ", ["spatial index(<q(c)>)" | c <- columns]);

str pp(index(str indexName, IndexKind kind, list[str] columns))
    = "<pp(kind)> index <q(fixLongName(indexName, indexName))>(<intercalate(", ", [q(c) | c <- columns])>)"
    when kind != spatial();
    
// IndexKind

str pp(uniqueIndex()) = "unique";  
str pp(fullText()) = "fulltext";  
str pp(regular()) = "";

// OnDelete

str pp(OnDelete::cascade()) = " on delete cascade";

str pp(OnDelete::nothing()) = "";


// ColumnConstraint

str pp(notNull()) = "not null";

str pp(unique()) = "unique";


// ColumnType

str pp(char(int size)) = "char(<size>)";
str pp(varchar(int size)) = "varchar(<size>)";
str pp(uuidType()) = "binary(16)";
str pp(text()) = "text";
str pp(integer()) = "integer";
str pp(bigint()) = "bigint";
str pp(float()) = "float";
str pp(double()) = "double";
str pp(blob()) = "longblob";
str pp(date()) = "date";
str pp(dateTime()) = "datetime";
str pp(point()) = "point";
str pp(polygon()) = "polygon";
str pp(boolean()) = "boolean";
