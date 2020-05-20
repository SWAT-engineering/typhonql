module lang::typhonql::cassandra::Query2CQL

import lang::typhonql::TDBC;
import lang::typhonql::Normalize;
import lang::typhonql::Order;
import lang::typhonql::Script;
import lang::typhonql::Session;

import lang::typhonml::Util;

import lang::typhonql::cassandra::CQL;
import lang::typhonql::cassandra::CQL2Text;
import lang::typhonql::cassandra::Schema2CQL;


import lang::typhonql::util::Log;

import String;
import ValueIO;
import DateTime;
import List;
import IO;


/*
 * Queries partitioned to cassandra
 * are simpler than ordinary queries
 * because there are no relations
 * in keyValue "entities".
 */

tuple[CQLStat, Bindings] compile2cql((Request)`<Query q>`, Schema s, Place p, Log log = noLog)
  = select2cql(q, s, p, log = log);

tuple[CQLStat, Bindings] select2csql((Query)`from <{Binding ","}+ bs> select <{Result ","}+ rs>`, Schema s, Place p, Log log = noLog) 
  = select2cql((Query)`from <{Binding ","}+ bs> select <{Result ","}+ rs> where true`, s, p, log = log);


tuple[CQLStat, Bindings] select2cql((Query)`from <{Binding ","}+ bs> select <{Result ","}+ rs> where <{Expr ","}+ ws>`
  , Schema s, Place p, Log log = noLog) {

  CQLStat q = cSelect([], "", []);
  
  void addWhere(CQLExpr e) {
    // println("ADDING where clause: <pp(e)>");
    q.wheres += [e];
  }
  
  void addResult(CQLSelectClause e) {
    q.selectClauses += [e];
  }
  
  int _vars = -1;
  int vars() {
    return _vars += 1;
  }

  Bindings params = ();
  void addParam(str x, Param field) {
    println("Adding param: <x> <field>");
    params[x] = field;
  }

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
  
  void recordResults(Expr e) {
    log("##### record results");
    visit (e) {
      case x:(Expr)`<VId y>`: {
         log("##### record results: var <y>");
    
         if (str ent := env["<y>"], <p, ent> <- ctx.schema.placement) {
           addResult(cSelector(expr2cql(x), as="<y>.<ent>.@id"));
           for (<ent, str a, str _> <- ctx.schema.attrs) {
             Id f = [Id]a;
             addResult(cSelector(expr2sql((Expr)`<VId y>.<Id f>`), as="<y>.<ent>.<f>"));
           }
         }
       }
      case x:(Expr)`<VId y>.@id`: {
         log("##### record results: var <y>.@id");
    
         if (str ent := env["<y>"], <p, ent> <- ctx.schema.placement) {
           addResult(cSelector(expr2cql(x), as="<y>.<ent>.@id"));
         }
      }
      case x:(Expr)`<VId y>.<Id f>`: {
         log("##### record results: <y>.<f>");
    
         if (str ent := env["<y>"], <p, ent> <- s.placement) {
           addResult(cSelector(expr2cql(x), as="<y>.<ent>.<f>"));
         }
      }
    }
  }

  // NB: if, not for, there can only be a single "from"
  myBindings = [ b | b:(Binding)`<EId e> <VId x>` <- bs ];
  if (size(myBindings) > 1) {
    throw "Currently subsets of entity attribute can only mapped to key-stores once per entity";
  }
  
  q.tableName = cTableName("<myBindings[0].entity>");

  for ((Result)`<Expr e>` <- rs) {
    switch (e) {
      case (Expr)`#done(<Expr x>)`: ;
      case (Expr)`#delayed(<Expr x>)`: ;
      case (Expr)`#needed(<Expr x>)`: 
        recordResults(x);
      default:
        recordResults(e);
    }
  }

  Expr rewriteDynIfNeeded(e:(Expr)`<VId x>.@id`) {
    if ("<x>" in dyns, str ent := env["<x>"], <Place p, ent> <- s.placement) {
      str token = "<x>_<vars()>";
      addParam(token, field(p.name, "<x>", env["<x>"], "@id"));
      return [Expr]"??<token>";
    }
    return e;
  }
  
  // todo: refactor this and above.
  Expr rewriteDynIfNeeded(e:(Expr)`<VId x>.<Id f>`) {
    if ("<x>" in dyns, str ent := env["<x>"], <Place p, ent> <- s.placement) {
      str token = "<x>_<vars()>";
      addParam(token, field(p.name, "<x>", env["<x>"], "@id"));
      return [Expr]"??<token>";
    }
    return e;
  }
  
  ws = visit (ws) {
    case (Expr)`<VId x>` => rewriteDynIfNeeded((Expr)`<VId x>.@id`)
    case e:(Expr)`<VId x>.@id` => rewriteDynIfNeeded(e)
    case e:(Expr)`<VId x>.<Id f>` => rewriteDynIfNeeded(e)
  }
  println("WHERES: <ws>");
  

  for (Expr e <- ws) {
    switch (e) {
      case (Expr)`#needed(<Expr x>)`:
        recordResults(x);
      case (Expr)`#done(<Expr _>)`: ;
      case (Expr)`#delayed(<Expr _>)`: ;
      default: 
        addWhere(expr2cql(e));
    }
  }
  
  // println("PARAMS: <params>");
  return <q, params>;
}
 

CQLExpr expr2cql((Expr)`<VId x>`) = expr2cql((Expr)`<VId x>.@id`);

// NB: hardcoding @id here, because no env abvailabe....
CQLExpr expr2cql((Expr)`<VId x>.@id`) = CQLExpr::cColumn("@id");

CQLExpr expr2cql((Expr)`<VId x>.<Id f>`) = CQLExpr::cColumn("<f>");

CQLExpr expr2cql((Expr)`?`) = cBindMarker();

CQLExpr expr2cql((Expr)`??<Id x>`) = cBindMarker(name="<x>");

CQLExpr expr2cql((Expr)`<Int i>`) = cTerm(cInteger(integer(toInt("<i>"))));

CQLExpr expr2cql((Expr)`<Real r>`) = cTerm(cFloat(toReal("<r>")));

CQLExpr expr2cql((Expr)`<Str s>`) = cTerm(cString("<s>"[1..-1]));

// a la cql timestamp
CQLExpr expr2cql((Expr)`<DateAndTime d>`) 
  = cTerm(cString(printDate(readTextValueString(#datetime, "<d>"), "yyyy-MM-dd\'T\'HH:mm:ss.SSSZZ")));

CQLExpr expr2cql((Expr)`<JustDate d>`)  
  = cTerm(cString(printDate(readTextValueString(#datetime, "<d>"), "yyyy-MM-dd")));

CQLExpr expr2cql((Expr)`<UUID u>`) = cTerm(cUUID("<u>"[1..]));

CQLExpr expr2cql((Expr)`true`) = cTerm(cBoolean(true));

CQLExpr expr2cql((Expr)`false`) = cTerm(cBoolean(false));

CQLExpr expr2cql((Expr)`(<Expr e>)`) = expr2cql(e);

CQLExpr expr2cql((Expr)`null`) = cTerm(cNull());

CQLExpr expr2cql((Expr)`+<Expr e>`) = expr2cql(e);

CQLExpr expr2cql((Expr)`-<Expr e>`) = cUminus(expr2cql(e));

//CQLExpr expr2cql((Expr)`!<Expr e>`) = not(expr2cql(e));

CQLExpr expr2cql((Expr)`<Expr lhs> * <Expr rhs>`) 
  = cTimes(expr2cql(lhs), expr2cql(rhs));

CQLExpr expr2cql((Expr)`<Expr lhs> / <Expr rhs>`) 
  = cDiv(expr2cql(lhs), expr2cql(rhs));

CQLExpr expr2cql((Expr)`<Expr lhs> + <Expr rhs>`) 
  = cAdd(expr2cql(lhs), expr2cql(rhs));

CQLExpr expr2cql((Expr)`<Expr lhs> - <Expr rhs>`) 
  = cMinus(expr2cql(lhs), expr2cql(rhs));

CQLExpr expr2cql((Expr)`<Expr lhs> == <Expr rhs>`) 
  = cEq(expr2cql(lhs), expr2cql(rhs));
  
CQLExpr expr2cql((Expr)`<Expr lhs> #join <Expr rhs>`)
  = cEq(expr2cql(lhs), expr2cql(rhs));
  

CQLExpr expr2cql((Expr)`<Expr lhs> != <Expr rhs>`) 
  = cNeq(expr2cql(lhs), expr2cql(rhs));

CQLExpr expr2cql((Expr)`<Expr lhs> \>= <Expr rhs>`) 
  = cGeq(expr2cql(lhs), expr2cql(rhs));

CQLExpr expr2cql((Expr)`<Expr lhs> \<= <Expr rhs>`) 
  = cLeq(expr2cql(lhs), expr2cql(rhs));

CQLExpr expr2cql((Expr)`<Expr lhs> \> <Expr rhs>`) 
  = cGt(expr2cql(lhs), expr2cql(rhs));

CQLExpr expr2cql((Expr)`<Expr lhs> \< <Expr rhs>`) 
  = cLt(expr2cql(lhs), expr2cql(rhs));

CQLExpr expr2cql((Expr)`<Expr lhs> in <Expr rhs>`)
  = cIn(expr2cql(lhs), expr2cql(rhs));


default CQLExpr expr2cql(Expr e) { throw "Unsupported expression: <e>"; }
