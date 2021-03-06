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

module lang::typhonql::Aggregation


import lang::typhonql::TDBC;
import lang::typhonql::Normalize;

import util::Maybe;
import IO;
import String;
import List;

/*


assumptions:
  - expansion of sole vars has happened
  - all aggregate functions are aliased with as
  - we have either a Result that's grouped on, or an aggregate result
  - having classes only refer to the alias names of aggregate results

from E1 e1, ..., En en
select xj.fj, ..., fi(...) as xi
where ... (only xj stuff)
group xm.fm, ...
having ... (includes xi's from fi(...)...)


split into:

from E1 e1, ..., En en
select xj.fj, ... + whatever is arg to fi aliased to xi
where ... (only xj stuff)


and

from E1 e1, ..., En en
select xj.fj, ..., fi(...) as xi
where true
group xm.fm, ...
having ... (includes xi's from fi(...)...)


*/

bool hasAggregation(Query q) 
  = (Agg _ <- q.aggClauses) || hasAggregationOps(q);

bool hasAggregationOps(Query q) 
  = (Result)`<VId _>(<{Expr ","}* _>) as <VId _>` <- q.selected; 

bool hasGroupBy(Query q) 
  = (Agg)`group <{Expr ","}+ _>` <- q.aggClauses; 

Query addGroupingIfNeeded(Query q) {
  if (hasAggregationOps(q), !hasGroupBy(q)) {
    switch (q) {
      case (Query)`from <{Binding ","}+ bs> select <{Result ","}+ rs> where <{Expr ","}+ conds> <Agg* aggs>`:
        return (Query)`from <{Binding ","}+ bs> select <{Result ","}+ rs> where <{Expr ","}+ conds> group null <Agg* aggs>`;
        
      case (Query)`from <{Binding ","}+ bs> select <{Result ","}+ rs> <Agg* aggs>`:
        return (Query)`from <{Binding ","}+ bs> select <{Result ","}+ rs> group null <Agg* aggs>`;
        
      default:
        throw "Bug: bad query <q>";
    }
  }
  return q;
}

list[Expr] whereExprs((Query)`from <{Binding ","}+ _> select <{Result ","}+ _> where <{Expr ","}+ conds> <Agg* _>`)
  = [ c | Expr c <- conds ];

default list[Expr] whereExprs(Query _)
  = [];
  
  

// we assume agg can be count, max, min, sum, avg
Result liftAgg((Result)`<VId agg>(<Expr e>) as <VId x>`) 
  = (Result)`<Expr e>`;


default Result liftAgg(Result r) = r;



tuple[Request, Maybe[Request]] extractAggregation(r:(Request)`<Query q>`) {
  q = addGroupingIfNeeded(q);
  if (hasAggregation(q)) {
    // deal with it
    
    list[Result] lifted = [ liftAgg(r) | Result r <- q.selected ];
     
    Query newQ = buildQuery([ b | Binding b <- q.bindings ]
      , lifted, whereExprs(q)); // NB: this is without group-by if any
       
    Query aggQ = buildQuery([ b | Binding b <- q.bindings ] 
      , [ r | Result r <- q.selected ] // the originals
      ,  []);
      
    if (Agg* aggs := q.aggClauses) {
      if ((Query)`from <{Binding ","}+ bs> select <{Result ","}+ rs> where <{Expr ","}+ conds>` := aggQ) {
        aggQ = (Query)`from <{Binding ","}+ bs> select <{Result ","}+ rs> where <{Expr ","}+ conds> <Agg* aggs>`;
      }
      else {
       throw "BUG: buildQuery returns Query that\'s not well-formed: <aggQ>";
      }
    } 
   
    return <(Request)`<Query newQ>`, just((Request)`<Query aggQ>`)>;
  }
  
  // no aggregation present
  return <r, nothing()>;
}

void testAggregationExtraction() {
  void printResult(tuple[Request, Maybe[Request]] result) {
    println("NORMAL: <result[0]>");
    println("AGGREG: <result[1] is just ? result[1].val : "nothing">");
    if (just(Request req) := result[1]) {
      println("JAVA:");
      println(aggregation2java(req, save=true));
    }
  }

  Request req = (Request)`from User u, Review r
                         'select u.name, count(r.@id) as rc
                         'where u.reviews == r.@id
                         'group u.name having rc \> 2`;
                         
                         
  printResult(extractAggregation(req));

  req = (Request)`from User u, Review r
                 'select u.name, u.age, count(r.@id) as rc
                 'where u.reviews == r.@id
                 'group u.age, u.name having rc \> 2 || rc \< 0`;
                         
                         
  printResult(extractAggregation(req));

  
  req = (Request)`from User u, Review r
                 'select u.name, r.@id
                 'where u.reviews == r.@id`;

  printResult(extractAggregation(req));

  req = (Request)`from Item i select i.shelf, count(i.@id) as numOfItems group i.shelf`; 

  printResult(extractAggregation(req));


  req = (Request)`from Item i, Product p select i.product, max(p.price) as total where i.product == p group i.product limit 10`;
  printResult(extractAggregation(req));
  
  req = (Request)`from Item i select i.shelf, count(i.@id) as numOfItems group i.shelf limit 0`;
  printResult(extractAggregation(req));
  
  req = (Request)`from Item i select i.shelf limit 2`;
  printResult(extractAggregation(req));
  
  req = (Request)`from Item i, Product p select i.product, max(p.price) as total 
                 'where i.product == p group i.product limit 10 order total`;
  printResult(extractAggregation(req));
  
  req = (Request)`from Item i, Product p select i.product, p.name, max(p.price) as total 
                 'where i.product == p group i.product limit 10 order p.name, total desc`;
  printResult(extractAggregation(req));
  
  req = (Request)`from Item i select i.shelf, i.@id limit 2 order i.shelf, i.@id`;
  printResult(extractAggregation(req));
  
  req = (Request)`from Item i select count(i) as c group null`;
  printResult(extractAggregation(req));

  req = (Request)`from Item i select count(i) as c`;
  printResult(extractAggregation(req));
    
    
}

map[Expr, int] mapGroupedToPos(list[Expr] gbs, list[Result] rs) {
  map[Expr, int] result = ();
  
  outer: for (Expr gb <- gbs) {
    for (int i <- [0..size(rs)]) {
      if ((Result)`<Expr e>` := rs[i], e := gb) {
        result[gb] = i;
        continue outer;
      } 
      if ((Result)`<Expr _> as <VId x>` := rs[i], (Expr)`<VId x>` := gb) {
        result[gb] = i;
        continue outer;
      }
      // else: ignore (e.g. nulls) 
    }
  }
  
  return result;
} 

//tuple[list[Result], list[Expr], list[Expr]] decomposeAgg(q:(Query)`from <{Binding ","}+ bs> select <{Result ","}+ rs> where true <GroupBy gb>`) {
//  <gbs, hs> = decomposeGroupBy(gb);
//  return <[ r | Result r <- rs ], gbs, hs>;
//}
//
//tuple[list[Expr], list[Expr]] decomposeGroupBy((Agg)`group <{Expr ","}+ gbs>`)
//  = <[ gb | Expr gb <- gbs ], []>;
//
//tuple[list[Expr], list[Expr]] decomposeGroupBy((Agg)`group <{Expr ","}+ gbs> having <{Expr ","}+ hs>`)
//  = <[ gb | Expr gb <- gbs ], [ h | Expr h <- hs ]>;


str aggregationClassName(bool suffix = false) = "AggregateIt<suffix ? "_" : "">";

str aggregationPkg() = "nl.cwi.swat.typhonql.backend.rascal";



/*
     java.util.List<java.lang.Object[]> $result = 
    		 $rows.limit(0).map((nl.cwi.swat.typhonql.backend.Record $x) -> { return new java.lang.Object[] { null }; }).collect(Collectors.toList());
*/


// this function assumes it is an aggregation query as result of extraction.
str aggregation2java(r:(Request)`<Query q>`, bool save = false) {
  list[Result] rs = [ r | Result r <- q.selected ];

  // TODO: to save memory: the shared fields via group by are already
  // in the key of the groupBy map, so don't have to be in 
  // the records per se anymore; however, constructing the
  // final result will be harder because we have to map
  // the key positions (derived from group by) back to the
  // original fields.
  str javaCode =   
    "package <aggregationPkg()>;
    '
    'public class <aggregationClassName(suffix=save)> implements <aggregationPkg()>.JavaOperationImplementation {
    '    
    '   public <aggregationClassName(suffix=save)>(nl.cwi.swat.typhonql.backend.ResultStore store, nl.cwi.swat.typhonql.backend.rascal.TyphonSessionState session
    '        , java.util.Map\<java.lang.String, java.util.UUID\> uuids) {
    '     // ???
    '   }
    '   
    '   @Override  
    '   public java.util.stream.Stream\<java.lang.Object[]\> processStream(
    '       java.util.List\<nl.cwi.swat.typhonql.backend.Field\> $fields,
    '       java.util.stream.Stream\<nl.cwi.swat.typhonql.backend.Record\> $rows) {
    '     //System.out.println(\"FIELDS: \" + $fields);
    '
    '     <if ((Agg)`group <{Expr ","}+ _>` <- q.aggClauses) {>
    '     java.util.List\<java.lang.Object[]\> $result = new java.util.ArrayList\<\>();
    '     <groupBysToJava([ e | (Agg)`group <{Expr ","}+ es>` <- q.aggClauses, Expr e <- es ], rs)>
    '     //System.out.println($grouped);
    '      
    '     for (java.util.List\<java.lang.Object\> $k: $grouped.keySet()) {
    '        java.util.List\<nl.cwi.swat.typhonql.backend.Record\> $records = $grouped.get($k);
    '        <aggs2vars(rs)>
    '        if (<havings2conds([ e | (Agg)`having <{Expr ","}+ es>` <- q.aggClauses, Expr e <- es ])>) {
    '          $result.add(<results2array("$records.get(0)", rs)>);
    '        }
    '     }
    '     return $result
    '       .stream()
    '       <if ((Agg)`order <{Expr ","}+ flds> <Dir dir>` <- q.aggClauses) {> 
    '       .sorted(<comparator([ f | Expr f <- flds], rs, dir, "java.lang.Object[]", fld2javaWithAggregation)>)
    '       <}>
    '       <if ((Agg)`offset <Int i>` <- q.aggClauses) {>
    '       .skip(<i>)
    '       <}>
    '       <if ((Agg)`limit <Int i>` <- q.aggClauses) {>
    '       .limit(<i>)
    '       <}>;
    '     <} else {>
    '       return $rows
    '       <if ((Agg)`order <{Expr ","}+ flds> <Dir dir>` <- q.aggClauses) {>
    '         .sorted(<comparator([ f | Expr f <- flds], rs, dir, "nl.cwi.swat.typhonql.backend.Record", fld2javaNoAggregation)>) 
    '       <}> 
    '       <if ((Agg)`offset <Int i>` <- q.aggClauses) {>
    '         .skip(<i>)
    '       <}>
    '       <if ((Agg)`limit <Int i>` <- q.aggClauses) {>
    '         .limit(<i>)
    '       <}>
    '         .map((nl.cwi.swat.typhonql.backend.Record $x) -\> 
    '            { return <results2array("$x", rs)>; });
    '     <} /* not having group-by */>
    '  }
    '}
    ";
    
  if (save) {
    str path = replaceAll(aggregationPkg(), ".", "/");
    writeFile(|project://typhonql/src/<path>/<aggregationClassName(suffix=true)>.java|, javaCode);
  }  
    
  return javaCode;
}

str fld2javaWithAggregation(str var, list[Result] rs, Expr fld) {
    int i = 0;
    for (Result r <- rs) {
      if ((Result)`<Expr _> as <VId x>` := r, (Expr)`<VId x>` := fld) {
        return "<var>[<i>]";
      }
      if ((Result)`<Expr e>` := r, e := fld) {
        return "<var>[<i>]";
      } 
      i += 1;
    }
    throw "No corresponding result of order expression <fld>";
}


str fld2javaNoAggregation(str var, list[Result] rs, Expr fld) {
    int i = 0;
    for (Result r <- rs) {
      // Cannot happen here
      //if ((Result)`<Expr _> as <VId x>` := r, (Expr)`<VId x>` := fld) {
      //  return result2var(r); // when ordering by an aggregation result
      //}
      if ((Result)`<Expr e>` := r, e := fld) {
        return "<var>.getObject($fields.get(<i>))";
      } 
      i += 1;
    }
    throw "No corresponding result of order expression <fld>";
}

str comparator(list[Expr] flds, list[Result] rs, Dir dir, str typ, str(str,list[Result], Expr) fld2java) {
  return 
    "new java.util.Comparator\<<typ>\>() {
    '  @SuppressWarnings({ \"rawtypes\", \"unchecked\" })
    '  public int compare(<typ> $o1, <typ> $o2) {
    '    int $comp = 0;
    '    <for (Expr fld <- flds) {>
    '    $comp = ((java.lang.Comparable)<fld2java("$o1", rs, fld)>)
    '       .compareTo((java.lang.Comparable)<fld2java("$o2", rs, fld)>);
    '    if ($comp != 0) {
    '      return <if ((Dir)`desc` := dir) {>-<}>$comp;
    '    }
    '    <}>
    '    return $comp;
    '  }
    '}";     
  
}


str results2array(str var, list[Result] rs)
  = "new java.lang.Object[] {<intercalate(", ", [ result2java(var, rs[i], i) | int i <- [0..size(rs)] ])>}";

// the var arg is not used, assuming that "as" is only used
// in aggregation (which should be enforced in the type checker).
str result2java(str _, (Result)`<Expr _> as <VId x>`, int _) = "<x>$";
  
// the default is that it's a non-aggregated result
// which means it's in the group by clause; hence
// in the current iteration over the keyset of $grouped
// all records have the same value; so we just take
// the field at position pos of the first record in
// $records (which is stored in $key).
default str result2java(str var, Result _, int pos) = "<var>.getObject($fields.get(<pos>))";




str havings2conds(list[Expr] hs)
  = ( "true" | "<it> && <having2cond(h)>" | Expr h <- hs );
  
// havings may only refer to aggregated data
// and in our case this is always aliased, so
// a variable ref always becomes a ref to an agg-var
str having2cond((Expr)`<VId x>`) = "<x>$";

str havingOps() = "<aggregationPkg()>.HavingOperators";

str having2cond((Expr)`<Expr lhs> \< <Expr rhs>`) 
  = "<havingOps()>.lt(<having2cond(lhs)>, <having2cond(rhs)>)";

str having2cond((Expr)`<Expr lhs> \<= <Expr rhs>`) 
  = "<havingOps()>.leq(<having2cond(lhs)>, <having2cond(rhs)>)";

str having2cond((Expr)`<Expr lhs> \> <Expr rhs>`) 
  = "<havingOps()>.gt(<having2cond(lhs)>, <having2cond(rhs)>)";

str having2cond((Expr)`<Expr lhs> \>= <Expr rhs>`) 
  = "<havingOps()>.geq(<having2cond(lhs)>, <having2cond(rhs)>)";

str having2cond((Expr)`<Expr lhs> == <Expr rhs>`) 
  = "<havingOps()>.eq(<having2cond(lhs)>, <having2cond(rhs)>)";

str having2cond((Expr)`<Expr lhs> != <Expr rhs>`) 
  = "<havingOps()>.neq(<having2cond(lhs)>, <having2cond(rhs)>)";

str having2cond((Expr)`<Expr lhs> && <Expr rhs>`) 
  = "<havingOps()>.and(<having2cond(lhs)>, <having2cond(rhs)>)";


str having2cond((Expr)`<Expr lhs> || <Expr rhs>`) 
  = "<havingOps()>.or(<having2cond(lhs)>, <having2cond(rhs)>)";

str having2cond((Expr)`<Int n>`) = "<n>";
//str having2cond((Expr)`-<Int n>`) = "-<n>";

str having2cond((Expr)`<Str s>`) = "<s>";

default str having2cond(Expr e) {
  throw "Unsupported `having`-condition: <e>";
}



str groupBysToJava(list[Expr] gbs, list[Result] rs) {
  map[Expr, int] pos = mapGroupedToPos( gbs, [ r | Result r <- rs ]);
  return groupBysToJava(gbs, pos);
}

str groupBysToJava(list[Expr] gbs, map[Expr, int] pos) 
  = "<nestedMap(gbs)> $grouped = <groupBysToGroupBys(gbs, pos)>;"; 


str result2var((Result)`<Expr agg> as <VId x>`) = "<x>$";

default str result2var((Result)`<Expr e>`) = expr2var(e);

str expr2var(e:(Expr)`<VId agg>(<Expr agg>)`) = "<agg>$<e@\loc.offset>";


str aggOps() = "<aggregationPkg()>.AggregationOperators";

// this is a bit brittle: we're assuming expression is a field ref
// that is at the position of this aggregation result because
// of the extraction of the previous (normal) query round
str agg2java((Expr)`<VId f>(<Expr arg>)`, int pos)
  = "<aggOps()>.<f>($records, $fields.get(<pos>))"
  when
    "<f>" in {"count", "sum", "avg", "max", "min"};
    
default str agg2java(Expr e, int pos) {
  throw "Cannot compile aggregation expression: <e>";
}
  
  

str aggs2vars(list[Result] rs) {
  s = "";
  for (int i <- [0..size(rs)]) {
    if (r:(Result)`<Expr agg> as <VId x>` := rs[i]) {
      s += "java.lang.Object <result2var(r)> = <agg2java(agg, i)>;\n";
      //s += "System.err.println(\"AGG: <agg> as <x> = \" + <agg2java(agg, i)>);"; 
    }
  } 
  return s;
}

str groupBysToGroupBys([(Expr)`null`], map[Expr,int] _)
  = "java.util.Collections.singletonMap(java.util.Collections.emptyList(), 
    '  $rows.collect(java.util.stream.Collectors.toList()))";
      
default str groupBysToGroupBys(list[Expr] gbs, map[Expr,int] pos) 
  = "$rows.collect(java.util.stream.Collectors.groupingBy((nl.cwi.swat.typhonql.backend.Record $x) -\> { 
    '   //System.out.println(\"CURRENT RECORD: \" + $x);
    '   //System.out.println(\"THE KEY: \" + java.util.Arrays.asList(<intercalate(", ", [ "$x.getObject($fields.get(<pos[gb]>))" | Expr gb <- gbs ])>));
    '   return java.util.Arrays.asList(<intercalate(", ", [ "$x.getObject($fields.get(<pos[gb]>))" | Expr gb <- gbs ])>); 
    '} , java.util.stream.Collectors.toList()))"; 
  
str nestedMap(list[Expr] gbs)
  = "java.util.Map\<java.util.List\<java.lang.Object\>, java.util.List\<nl.cwi.swat.typhonql.backend.Record\>\>";
  


    