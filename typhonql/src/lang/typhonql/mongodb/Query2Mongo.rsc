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

module lang::typhonql::mongodb::Query2Mongo

import lang::typhonql::TDBC;
import lang::typhonql::Order;
import lang::typhonql::Normalize;

import lang::typhonql::Session;
import lang::typhonml::TyphonML;
import lang::typhonml::Util;
import lang::typhonql::mongodb::DBCollection;
import lang::typhonql::util::Strings;
import lang::typhonql::util::Dates;

import List;
import ValueIO;
import IO;
import String;
import util::Math;

////////
/////// TODO: normalization (e.g. expandNavigation) is SQL specific
/// for Mongo we need the paths.
/// so what if we always do SQL first, and then mongo, and
/// 
//////


/*

What if we totally restrict TyphonQL select for Mongo so that it matches Find?

from E x select x.a.b.c, x.f.b.c where 



*/

tuple[map[str, CollMethod], Bindings] compile2mongo(r:(Request)`<Query q>`, Schema s, Place p)
  = select2mongo(r, s, p);


alias Ctx = tuple[
    str(str,Param) getParam,
    Schema schema,
    Env env,
    set[str] dyns,
    int() vars,
    Place place,
    str root];
    
    
Request unjoinWheres(req:(Request)`from <{Binding ","}+ bs> select <{Result ","}+ rs> where <{Expr ","}+ ws>`, Schema s) {
  // replace #join expressions with .-navigations, basically undoing expandNavigation
  
  Expr unjoin(Expr e, VId x) {
    return top-down-break visit (e) {
       case (Expr)`#done(<Expr _>)`: ;
       case (Expr)`#needed(<Expr _>)`: ;
       case (Expr)`#delayed(<Expr _>)`: ;
       
       case (Expr)`<Expr lhs> #join <Expr rhs>` => (Expr)`<Expr lhs2> #join <Expr rhs>` 
          when Expr lhs2 := unjoin(lhs, x)
        
       case (Expr)`<VId x1>.<Id f>` => (Expr)`<VId var>.<{Id "."}+ fs2>.<Id f>`
         when x1 == x, (Expr)`<VId var>.<{Id "."}+ fs2> #join <VId x2>` <- ws, x2 == x
    }
  }
  
  for ((Binding)`<EId _> <VId x>` <- bs) { // skipping dynamic ones
    // everywhere x occurs, and a  `E #join x` exists, replace x with E (but not in rhs of #join itself)
    //println("Trying to unjoin <e> <x>");
    req = top-down-break visit (req) {
       case Expr e => unjoin(e, x)
    }
  }
  
  bool isLocalHashJoin(Expr w) {
     if (!(w is hashjoin)) {
       return false;
     }
     // only return false for the outermost join
     // from a dynamic variable, that's why we
     // don't match on a seq of {Id ","}+
    
     if ((Expr)`<VId x>.<Id _> #join <Expr rhs>` := w) {
       if ((Binding)`#dynamic(<EId _> <VId x2>)` <- bs, x == x2) {
         return false;
       }
     }
     return true;
  }
  
  if ((Request)`from <{Binding ","}+ bs2> select <{Result ","}+ rs2> where <{Expr ","}+ ws2>` := req) {
    q = buildQuery([ b | Binding b <- bs2 ], [ r | Result r <- rs2 ], 
       [ w | Expr w <- ws2, !isLocalHashJoin(w) ]);
       
    return (Request)`<Query q>`;
  }
  throw "Bad pattern match on request: <req>";
}

tuple[map[str, CollMethod], Bindings] select2mongo((Request)`from <{Binding ","}+ bs> select <{Result ","}+ rs>`, Schema s, Place p) 
  = select2mongo((Request)`from <{Binding ","}+ bs> select <{Result ","}+ rs> where true`, s, p); 

tuple[map[str, CollMethod], Bindings] select2mongo(req:(Request)`from <{Binding ","}+ bs> select <{Result ","}+ rs> where <{Expr ","}+ ws>`, Schema s, Place p) 
  = select2mongo_(unjoinWheres(req, s), s, p);  
    
tuple[map[str, CollMethod], Bindings] select2mongo_(req:(Request)`from <{Binding ","}+ bs> select <{Result ","}+ rs> where <{Expr ","}+ ws>`, Schema s, Place p) {
  //println("TOMONGO: <req>");
  
  Env env = (); 
  set[str] dyns = {};
  
  for (Binding b <- bs) {
    switch (b) {
      case (Binding)`<EId e> <VId x>`:
        env["<x>"] = "<e>";
      case (Binding)`#dynamic(<EId e> <VId x>)`: {
        env["<x>"] = "<e>";
        dyns += {"<x>"};
      }
      case (Binding)`#ignored(<EId e> <VId x>)`:
        env["<x>"] = "<e>";
    }
  }
  
  // mapping entity name to <collectionName, subPath> tuples
  map[str, tuple[str root, list[str] path]] paths
    =  ( "<e>" : localPathToEntity("<e>", s, p) | (Binding)`<EId e> <VId x>` <- bs );
    
  // mapping collection name to methods (i.e. `find`)
  map[str, CollMethod] result = ( paths["<e>"].root : find(object([]), object([<"_id", \value(1)>])) | (Binding)`<EId e> <VId x>` <- bs );
  
  void addConstraint(str ent, object([<str opOrPath, DBObject val>])) {
    // todo: if the path is already in props, create $and obj 
    prePath = paths[ent].path;
    if (prePath != []) {
      if (opOrPath in {"$or", "$and", "$not"}) {
        throw "BUG: trying to interpret boolean connective as path";
      }
      path = "<intercalate(".", paths[ent].path)>.<opOrPath>";
    }
    if (result[paths[ent].root].query.props == []) {
      result[paths[ent].root].query.props += [<opOrPath, val>];
    }
    else if ([<str p, DBObject constraint>] := result[paths[ent].root].query.props, p != "$and") { // make $and
      result[paths[ent].root].query.props = [<"$and", array([object([<p, constraint>]), object([<opOrPath, val>])])>];
    }
    else if ([<"$and", array(list[DBObject] constraints)>] := result[paths[ent].root].query.props) { 
      result[paths[ent].root].query.props = [<"$and", array([*constraints, object([<opOrPath, val>])])>];
    }
  }
  
  
  bool isLocal(VId x) = (str ent := env["<x>"] && <p, ent> <- s.placement);
    
  void addProjection(VId x, str fields) {
    /*
     Here we are assuming the non-annotated result clauses are in fact
     on the collection we're querying, so we have to strip of the
     path from the front up-till the entity that we're querying on
     so p.reviews.contents becomes a projection "contents", because
     the current collection is Review, and p.reviews leads to that.
    */
    
    str ent = env["<x>"];
    
    if (!isLocal(x)) {
      list[str] fs = split(".", fields); // ugh
      
      while (ent notin paths) {
         if (fs == []) {
           throw "Could not find entity in current maps of collections";
         }
         role = fs[0];
         if (<ent, _, role, _, _, str to, _> <- s.rels) {
           ent = to;
           fs = fs[1..];
         }
         else {
           println("No such role <role> for <ent> in schema");
         return;

         }
      }
      fields = intercalate(".", fs);
    }
    
    prePath = paths[ent].path;
    
    Prop prop = <fields, \value(1)>;
    if (prePath != []) {
      prop = <"<intercalate(".", paths[ent].path)>.<fields>", \value(1)>;
    }
    // not sure where the empty string comes from...
    if (prop.name != "", prop notin result[paths[ent].root].projection.props) {
      result[paths[ent].root].projection.props += [prop];
    }
  } 
  
  void recordProjections(Expr e) {
     top-down-break visit (e) {
      case (Expr)`#done(<Expr _>)`: ;
      case (Expr)`#delayed(<Expr _>)`: ;
      case x:(Expr)`<VId y>`: {
         // TODO: there is a difference between y in result and y in where clauses
         // --> fix normalization to desguar y in where clauses to y.@id, 
         // and in result to all attrs.
         addProjection(y, "_id");
      }
      case x:(Expr)`<VId y>.@id`:
         addProjection(y, "_id");
      case x:(Expr)`<VId y>.<{Id "."}+ fs>`:
         addProjection(y, "<fs>");

    }
  }

  // NB: VId x is local, because otherwise it would be dynamic or ignored
  // strong assumption here is that dot-notation is local and only containment
  for ((Result)`<Expr e>` <- rs) {
    recordProjections(e);
  }

  for ((Result)`#needed(<Expr e>)` <- rs) {
    recordProjections(e);
  }

  
  int _vars = -1;
  int vars() {
    return _vars += 1;
  }
  
  Bindings params = (); 
  void addParam(str x, Param field) {
    params[x] = field;
  }
  
  map[Param, str] placeholders = ();
  str getParam(str prefix, Param field) {
    if (field notin placeholders) {
      str name = "<prefix>_<vars()>";
      placeholders[field] = name;
      addParam(name, field);
    } 
    return placeholders[field];
  }
  
  
  /*
  // the root entity is the entity that corresponds to a collection
  // in Mongo; there can only be one, all other non dynamic bindings should
  // be reachable via containment paths,
   
  So for instance
  
  from Review r select r.comments.contents where r.comments.contents == ""
  normalizes into
  from Review r, Comment c select c.contents where r.comments == c, c.contents == "";
   
  this will have to add a constraint (TODO: with $exists somehow because there are multiple comments)
  {"comments.contents": ""}
  
  So we have evaluate the joining where clauses to find the path from root
  to the entity that has the constraint on the attribute 
  */
  root = "";
   
  
  Ctx ctx = <
    getParam,
    s,
    env,
    dyns,
    vars,
    p, 
    root>;
  
    
  
  
  
  for (Expr e <- ws) {
    switch (e) {
      case (Expr)`#done(<Expr _>)`: ;
      case (Expr)`#delayed(<Expr _>)`: ;
      case (Expr)`#needed(<Expr x>)`: 
        recordProjections(x);

      default: {
        if ((Expr)`true` !:= e) {
          <ent, obj> = expr2pattern(e, ctx);
          addConstraint(ent, obj);
        }   
      }
    }
      
  }
  
  //println("*****RESULT ****");
  //iprintln(result);
  
  return <result, params>;
}


tuple[str, DBObject] expr2pattern((Expr)`<Expr lhs> #join <Expr rhs>`, Ctx ctx)
  = expr2pattern((Expr)`<Expr lhs> == <Expr rhs>`, ctx);
  
tuple[str, DBObject] expr2pattern((Expr)`<Expr lhs> == <Expr rhs>`, Ctx ctx)
  = <ent, object([<path, expr2obj(other, ctx)>])> 
  when
    <str ent, str path, Expr other> := split(lhs, rhs, ctx);

tuple[str, DBObject] expr2pattern((Expr)`<Expr lhs> || <Expr rhs>`, Ctx ctx) {
  <ent, obj1> = expr2pattern(lhs, ctx);
  <ent, obj2> = expr2pattern(rhs, ctx);
  return <ent, object([<"$or", array([obj1, obj2])>])>;
}

tuple[str, DBObject] expr2pattern((Expr)`<Expr lhs> && <Expr rhs>`, Ctx ctx) {
  <ent, obj1> = expr2pattern(lhs, ctx);
  <ent, obj2> = expr2pattern(rhs, ctx);
  return <ent, object([<"$and", array([obj1, obj2])>])>;
}

tuple[str, DBObject] expr2pattern((Expr)`(<Expr e>)`, Ctx ctx)
  = expr2pattern(e, ctx);
    
tuple[str, DBObject] expr2pattern((Expr)`<Expr lhs> != <Expr rhs>`, Ctx ctx)
  = makeComparison("$ne", lhs, rhs, ctx);

tuple[str, DBObject] expr2pattern((Expr)`<Expr lhs> \> <Expr rhs>`, Ctx ctx)
  = makeComparison("$gt", lhs, rhs, ctx);

tuple[str, DBObject] expr2pattern((Expr)`<Expr lhs> \< <Expr rhs>`, Ctx ctx)
  = makeComparison("$lt", lhs, rhs, ctx);

tuple[str, DBObject] expr2pattern((Expr)`<Expr lhs> \>= <Expr rhs>`, Ctx ctx)
  = makeComparison("$gte", lhs, rhs, ctx);

tuple[str, DBObject] expr2pattern((Expr)`<Expr lhs> \<= <Expr rhs>`, Ctx ctx)
  = makeComparison("$lte", lhs, rhs, ctx);

tuple[str, DBObject] expr2pattern((Expr)`<Expr lhs> in <Expr rhs>`, Ctx ctx) {
  <ent, path, other> = split(lhs, rhs, ctx);
  return <ent, object([<path, object([
            <"$geoWithin", object([
                <"$geometry", expr2obj(other, ctx)>
            ])>
        ])>])>; 
}
  
tuple[str, DBObject] expr2pattern((Expr)`<Expr lhs> & <Expr rhs>`, Ctx ctx) {
   <ent, path, other> = split(lhs, rhs, ctx);
   return <ent, object([<path, object([
            <"$geoIntersects", object([
                <"$geometry", expr2obj(other, ctx)>
            ])>
        ])>])>;
}

// TODO: &&, ||, in, like

default tuple[str, DBObject] expr2pattern(Expr e, Ctx ctx) { 
  throw "Unsupported expression in MongoDB: <e>"; 
}


  
tuple[str, DBObject] makeComparison(str op, Expr lhs, Expr rhs, Ctx ctx) 
  = <ent, object([<path, object([<op, expr2obj(other, ctx)>])>])> 
  when !isGeoDistanceCall(lhs), !isGeoDistanceCall(rhs),
    <str ent, str path, Expr other> := split(lhs, rhs, ctx);


bool isGeoDistanceCall((Expr)`distance(<Expr _>, <Expr _>)`) = true;
default bool isGeoDistanceCall(_) = false;

tuple[tuple[str ent, str path, Expr other] ori, Expr other2] 
    distanceSplit((Expr)`distance(<Expr lhs1>, <Expr rhs1>)`, Expr rhs, Ctx ctx)
    = <split(lhs1, rhs1, ctx), rhs>;
    

tuple[tuple[str ent, str path, Expr other] ori, Expr other2] 
    distanceSplit(Expr lhs, (Expr)`distance(<Expr lhs1>, <Expr rhs1>)`, Ctx ctx)
    = <split(lhs1, rhs1, ctx), lhs>;

str translateOp("$gte") = "$minDistance";
str translateOp("$gt") = "$minDistance";
str translateOp("$lt") = "$maxDistance";
str translateOp("$lte") = "$maxDistance";
default str translateOp(str op) { throw "<op> not supported for distance clause, only \<, \<=, \>, and \>= are supported"; }

tuple[str, DBObject] makeComparison(str op, Expr lhs, Expr rhs, Ctx ctx) 
    = <ent, object([<path, object([
        <"$nearSphere", object([
            <"$geometry", expr2obj(other, ctx)>, 
            <translateOp(op), expr2obj(other2, ctx)>
            ])>
      ])>])>
    when isGeoDistanceCall(lhs) || isGeoDistanceCall(rhs),
        <<str ent, str path, Expr other>, Expr other2> := distanceSplit(lhs, rhs, ctx);
    

// NB: restriction is that the same collection cannot be queried with different vars
// also paths in vars now must end at  primitives.
 
tuple[str ent, str path, Expr other] split(Expr lhs, Expr rhs, Ctx ctx) {
  if ((Expr)`<VId x>.<{Id "."}+ fs>` := lhs, "<x>" notin ctx.dyns) {
    return <ctx.env["<x>"], "<fs>", rhs>; 
  }
  if ((Expr)`<VId x>.@id` := lhs, "<x>" notin ctx.dyns) {
    return <ctx.env["<x>"], "_id", rhs>; 
  }

  if ((Expr)`<VId x>` := lhs, "<x>" notin ctx.dyns) {
    return <ctx.env["<x>"], "_id", rhs>;
  } 

  if ((Expr)`<VId x>.<{Id "."}+ fs>` := rhs, "<x>" notin ctx.dyns) {
    return <ctx.env["<x>"], "<fs>", lhs>;
  }
  if ((Expr)`<VId x>.@id` := rhs, "<x>" notin ctx.dyns) {
    return <ctx.env["<x>"], "_id", lhs>; 
  }

  if ((Expr)`<VId x>` := rhs, "<x>" notin ctx.dyns) {
    return <ctx.env["<x>"], "_id", lhs>; 
  }
  
  
  throw "One of binary expr must contain field navigation, but got: `<lhs>` and `<rhs>`";
}    

DBObject expr2obj(e:(Expr)`<VId x>.<{Id "."}+ fs>`, Ctx ctx) {
  if ("<x>" in ctx.dyns, str ent := ctx.env["<x>"], <Place p, ent> <- ctx.schema.placement) {
    str token = ctx.getParam("<x>_<fs>", field(p.name, "<x>", ctx.env["<x>"], "<fs>"));
    return placeholder(name=token);
  }
  throw "Only dynamic parameters can be used as expressions in query docs, not <e>";
}

DBObject expr2obj(e:(Expr)`<VId x>`, Ctx ctx) 
  = expr2obj((Expr)`<VId x>.@id`, ctx);

DBObject expr2obj(e:(Expr)`<VId x>.@id`, Ctx ctx) {
  if ("<x>" in ctx.dyns, str ent := ctx.env["<x>"], <Place p, ent> <- ctx.schema.placement) {
    str token = ctx.getParam("<x>_@id", field(p.name, "<x>", ctx.env["<x>"], "@id"));
    return placeholder(name=token);
  }
  throw "Only dynamic parameters can be used as expressions in query docs, not <e>";
}

DBObject expr2obj((Expr)`<PlaceHolder ph>`, Ctx _) = DBObject::placeholder(name = "<ph.name>");
DBObject expr2obj((Expr)`<UUID id>`, Ctx _) = mUuid("<id.part>");

DBObject expr2obj((Expr)`<DateTime d>`, Ctx _) = \value(convert(d));

DBObject expr2obj((Expr)`<Int i>`, Ctx _) = \value(toInt("<i>"));

DBObject expr2obj((Expr)`<Real r>`, Ctx _) = \value(toReal("<r>"));

DBObject expr2obj((Expr)`#blob:<UUIDPart prt>`, Ctx _) = \value("#blob:<prt>");

// warning, clones of Insert2Script!
DBObject expr2obj((Expr)`#point(<Real x> <Real y>)`, _) 
  = object([<"type", \value("Point")>, 
      <"coordinates", array([\value(toReal("<x>")), \value(toReal("<y>"))])>]);

DBObject expr2obj((Expr)`#polygon(<{Segment ","}* segs>)`, _) 
  = object([<"type", \value("Polygon")>,
      <"coordinates", array([ seg2array(s) | Segment s <- segs ])>]);


DBObject seg2array((Segment)`(<{XY ","}* xys>)`)
  = array([ array([\value(toReal("<x>")), \value(toReal("<y>"))]) | (XY)`<Real x> <Real y>` <- xys ]);

// todo: unescaping
DBObject expr2obj((Expr)`<Str s>`, Ctx _) = \value(unescapeQLString(s));

DBObject expr2obj((Expr)`<Bool b>`, Ctx _) = \value("<b>" == "true");

default DBObject expr2obj(Expr e, Ctx _) { throw "Unsupported MongoDB restriction expression: <e>"; }
