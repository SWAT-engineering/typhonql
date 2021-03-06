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

module lang::typhonql::Request2Script


import lang::typhonml::Util;
import lang::typhonml::TyphonML;
import lang::typhonql::Script;
import lang::typhonql::Session;
import lang::typhonql::TDBC;
import lang::typhonql::Order;
import lang::typhonql::Normalize;

import lang::typhonql::Insert2Script;
import lang::typhonql::Update2Script;
import lang::typhonql::Delete2Script;
import lang::typhonql::Query2Script;
import lang::typhonql::DDL2Script;
import lang::typhonql::Aggregation;


import lang::typhonql::relational::SQL;
import lang::typhonql::relational::Util;
import lang::typhonql::relational::SQL2Text;
import lang::typhonql::relational::Query2SQL;

import lang::typhonql::mongodb::Query2Mongo;
import lang::typhonql::mongodb::DBCollection;

import lang::typhonql::neo4j::Query2Neo;
import lang::typhonql::neo4j::Neo2Text;
import lang::typhonql::neo4j::Neo;


import lang::typhonql::util::Log;

import IO;
import List;
import util::Maybe;

/*

TODO:

- modularize using pattern-based dispatch
- use toRole matching to "" to determine the canonical relation in case of non-ownership
- clean-up the PARAM string passing
- custom data type expansion
- NLP hooks

*/


bool hitsBackend((Request)`<Query q>`, Place p, Schema s) 
  = ( false | it || (<p, "<b.entity>"> in s.placement) | Binding b <- q.bindings );


Script request2script(Request r, Schema s, Log log = noLog) {
  log("REQ: <r>");

  r = eliminateCustomDataTypes(injectProperUUIDs(r), s);

  switch (r) {

    case (Request)`<Query q>`: {
      Maybe[Request] maybeAgg = Maybe::nothing();
      if (hasAggregation(q)) {
        // NB: we're hard updating r here...
        <r, maybeAgg> = extractAggregation(r);
      }
         
      list[Place] order = orderPlaces(r, s);
      r = addWhereIfAbsent(r);
      r = flattenAndsToCommas(r);
      r = expandNavigation(inferNlpLinks(inferKeyValLinks(expandLoneVars(r, s), s), s), s);
      r = explicitJoinsInReachability(r, s);
      r = eliminateCustomDataTypes(expandLoneCustoms(injectProperUUIDs(r), s), s);
      log("NORMALIZED: <r>");
      log("ORDER: <order>");
      log("PLACEMENTS: <s.placement>");
      

	  Script scr = script([]);
	  
	  set[Place] backendsHit(list[Place] order, Request r, Schema s) {
	     return { p | Place p <- order, hitsBackend(r, p, s) };
	  }

	  if ({p:<DB::mongodb(), _>} := backendsHit(order, r, s), just(Request aggReq) := maybeAgg) {
	    // strictly Mongo
	    scr = script(compileQuery(r, p, s, log = log, agg = maybeAgg));
	    list[Path] paths = results2pathsWithAggregation(aggReq.qry.selected, queryEnv(aggReq.qry), s);
	    scr.steps += [read(paths)];
	  }
	  else if ({p:<DB::sql(), _>} := backendsHit(order, r, s), just(Request aggReq) := maybeAgg) {
	    // strictly SQL 
	    scr = script(compileQuery(r, p, s, log = log, agg = maybeAgg));
	    list[Path] paths = results2pathsWithAggregation(aggReq.qry.selected, queryEnv(aggReq.qry), s);
	    scr.steps += [read(paths)]; 
	  }
	  else {
	    scr = script([ *compileQuery(restrict(r, p, order, s), p, s, log = log) 
          | Place p <- order, hitsBackend(r, p, s)]);
          
        list[Path] paths = results2paths(r.qry.selected, queryEnv(r.qry), s);
         
        if (just(aggReq:(Request)`<Query agg>`) := maybeAgg) {
          list[str] finalCols = results2colNames(agg.selected, queryEnv(agg), s);
        
          scr.steps += [javaRead("<aggregationPkg()>.<aggregationClassName()>", aggregation2java(aggReq), paths, finalCols)];   
        }
        else {
          scr.steps += [read(paths)];
        }
        
      }
      
       
      return scr;
    }

    case (Request)`update <EId e> <VId x> set {<{KeyVal ","}* kvs>}`: {
      return request2script((Request)`update <EId e> <VId x> where true set {<{KeyVal ","}* kvs>}`, s);
    }

    case (Request)`update <EId e> <VId x> where <{Expr ","}+ ws> set {<{KeyVal ","}* kvs>}`:
      return update2script(r, s);


    case (Request)`delete <EId e> <VId x>`: {
	  return request2script((Request)`delete <EId e> <VId x> where true`, s);
	}

	case (Request)`delete <EId e> <VId x> where <{Expr ","}+ ws>`:
	  return delete2script(r, s);

    case (Request)`insert <EId e> { <{KeyVal ","}* kvs> }`:
       return insert2script(addDefaultsForOmittedAttrs(r, s), s); 
    
    default: 
      //throw "Unsupported request: `<r>`";
      return ddl2script(r, s);
  }
}



void smokeScript() {
  s = schema(
  { "Review", "Person", "Comment", "SomeStuff", "Cash", "Reply" },
  {
    <"Person", zero_many(), "reviews", "user", \one(), "Review", true>,
    <"Person", zero_many(), "cash", "owner", \one(), "Cash", true>,
    <"Person", \one(), "SomeStuff__", "", \one(), "SomeStuff", true>,
    <"Review", \one(), "user", "reviews", \zero_many(), "Person", false>,
    <"Review", \one(), "comment", "owner", \zero_many(), "Comment", true>,
    <"Comment", zero_many(), "replies", "owner", \zero_many(), "Comment", true>
  }, {
    <"Person", "name", "text">,
    <"Person", "age", "int">,
    <"Item", "shelf", "int">,
    <"SomeStuff", "photo", "text">,
    <"SomeStuff", "bitcoin", "text">,
    <"Cash", "amount", "int">,
    <"Review", "text", "text">,
    <"Comment", "contents", "text">,
    <"Reply", "reply", "text">
  },
  placement = {
    <<cassandra(), "Stuff">, "SomeStuff">,
    <<sql(), "Inventory">, "Person">,
    <<sql(), "Inventory">, "Cash">,
    <<sql(), "Inventory">, "Item">,
    <<mongodb(), "Reviews">, "Review">,
    <<mongodb(), "Reviews">, "Comment">
  }
  );

  void smokeIt(Request q) {
    println("REQUEST: `<q>`");
    iprintln(request2script(q, s));
  }



  smokeIt((Request)`delete Review r`);


  smokeIt((Request)`delete Review r where r.text == "Bad"`);

  smokeIt((Request)`delete Comment c where c.contents == "Bad"`);

  smokeIt((Request)`delete Person p`);

  smokeIt((Request)`delete Person p where p.name == "Pablo"`);

  smokeIt((Request)`update Person p set {name: "Pablo"}`);

  smokeIt((Request)`update Person p set {name: "Pablo", age: 23}`);


  smokeIt((Request)`update Person p where p.name == "Pablo" set {reviews +: [#abc, #cde]}`);

  smokeIt((Request)`update Person p where p.name == "Pablo" set {reviews -: [#abc, #cde]}`);

  smokeIt((Request)`update Person p where p.name == "Pablo" set {reviews: [#abc, #cde]}`);

  smokeIt((Request)`update Review r set {text: "bad"}`);

  smokeIt((Request)`update Review r where r.text == "Good" set {text: "Bad"}`);

  smokeIt((Request)`update Person p set {name: "Pablo", cash: [#abc, #cde]}`);

  smokeIt((Request)`update Person p set {name: "Pablo", cash +: [#abc, #cde]}`);

  smokeIt((Request)`update Person p set {name: "Pablo", cash -: [#abc, #cde]}`);

  smokeIt((Request)`update Person p where p.name == "Pablo" set {reviews -: [#abc, #cde]}`);

  smokeIt((Request)`update Person p where p.name == "Pablo" set {reviews +: [#abc, #cde], reviews -: [#xyz]}`);

  smokeIt((Request)`update Person p where p.name == "Pablo" set {reviews -: [#abc, #cde], name: "Pete"}`);

  smokeIt((Request)`update Person p where p.name == "Pablo" set {reviews -: [#abc, #cde], age: 32, name: "Bla"}`);

  smokeIt((Request)`update Person p where p.name == "Pablo" set {cash: [#dollar]}`);
  smokeIt((Request)`update Person p where p.name == "Pablo" set {cash +: [#dollar]}`);
  smokeIt((Request)`update Person p where p.name == "Pablo" set {cash -: [#dollar]}`);

  smokeIt((Request)`update Cash c where c.amount \> 0 set {owner: #pablo}`);

  smokeIt((Request)`update Cash c where c.@id == #dollar  set {owner: #pablo}`);

  smokeIt((Request)`update Comment c where c.@id == #stupid set { replies: [#abc1, #cdef2] }`);

  smokeIt((Request)`update Comment c where c.@id == #stupid set { replies +: [#abc1, #cdef2] }`);

  smokeIt((Request)`update Comment c where c.@id == #stupid set { replies -: [#abc1, #cdef2] }`);



  smokeIt((Request)`delete Person p where p.name == "Pablo"`);

  smokeIt((Request)`insert Person {name: "Pablo", age: 23}`);
  smokeIt((Request)`insert Person {name: "Pablo", age: 23, reviews: #abc, reviews: #cdef}`);

  smokeIt((Request)`insert Review {text: "Bad"}`);

  smokeIt((Request)`insert Person {name: "Pablo", age: 23, @id: #pablo}`);

  smokeIt((Request)`insert Review {text: "Bad", user: #pablo}`);


  smokeIt((Request)`insert Person {name: "Pablo", age: 23}`);
  smokeIt((Request)`insert Person {name: "Pablo", age: 23, reviews: [#abc, #cdef]}`);

  smokeIt((Request)`insert Review {text: "Bad", user: #pablo}`);

  smokeIt((Request)`update Person p set {name: "Pablo"}`);

  smokeIt((Request)`update Person p set {name: "Pablo", age: 23}`);



  smokeIt((Request)`from Person p, Review r select r.text, p.name where p.name == "Pablo", p.reviews == r`);

  smokeIt((Request)`from Person p, Review r select r.text, p.name where p.name == "Pablo", p.reviews == r`);

  smokeIt((Request)`from Person u, Review r select r where r.user == u, u.name == "Pablo"`);

  smokeIt((Request)`from Person p, Review r select r.text, p.name where p.name == "Pablo", p.reviews == r`);

  smokeIt((Request)`from Person p, Cash c select p.name where p.name == "Pablo", p.cash == c, c.amount \> 0`);


  smokeIt((Request)`from Person u, Review r select u.name, r.user where u.reviews == r, r.text == ""`);

  smokeIt((Request)`from Person p select p.reviews where p == #victor`);

  smokeIt((Request)`insert Person {name: "Pablo", age: 23, photo: "hello"}`);
  
  smokeIt((Request)`insert Person {name: "Pablo", age: 23, photo: "hello", bitcoin: "bla"}`);
 
 
  smokeIt((Request)`delete Review r`);

  smokeIt((Request)`delete Review r where r.text == "Bad"`);

  smokeIt((Request)`delete Comment c where c.contents == "Bad"`);

  smokeIt((Request)`delete Person p`);

  smokeIt((Request)`delete Person p where p.name == "Pablo"`);
 
  
  smokeIt((Request)`from Person p, Review r select r.text, p.name where p.name == "Pablo", p.reviews == r`);

  smokeIt((Request)`from Person p, Review r select r.text, p.name where p.name == "Pablo", p.reviews == r`);

  smokeIt((Request)`from Person u, Review r select r where r.user == u, u.name == "Pablo"`);

  smokeIt((Request)`from Person p, Review r select r.text, p.name where p.name == "Pablo", p.reviews == r`);

  smokeIt((Request)`from Person p, Cash c select p.name where p.name == "Pablo", p.cash == c, c.amount \> 0`);


  smokeIt((Request)`from Person u, Review r select u.name, r.user where u.reviews == r, r.text == ""`);

  smokeIt((Request)`from Person p select p.reviews where p == #victor`);

  smokeIt((Request)`from Person p select p.photo where p == #victor`);

  smokeIt((Request)`from Person p select p.photo, p.bitcoin where p == #victor`);

  smokeIt((Request)`update Person p where u.@id == #pablo set {photo: "MOUSTACHE"}`);
  
  smokeIt((Request)`from Person u, Review r
                   'select u.name, count(r.@id) as rc
                   'where u.reviews == r.@id
                   'group u.name having rc \> 2`);
                         
                         

  smokeIt((Request)`from Person u, Review r
                 'select u.name, u.age, count(r.@id) as rc
                 'where u.reviews == r.@id
                 'group u.age, u.name having rc \> 2 || rc \< 0`);
                         
    
  smokeIt((Request)`from Item i select i.shelf, count(i.@id) as numOfItems group i.shelf`);
  
}
