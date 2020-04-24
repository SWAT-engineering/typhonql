module lang::typhonql::RunUsingCompiler


import lang::typhonml::Util;
import lang::typhonml::TyphonML;

import lang::typhonql::Partition;
import lang::typhonql::TDBC;
import lang::typhonql::DDL;
import lang::typhonql::Session;
import lang::typhonql::Request2Script;
import lang::typhonql::Schema2Script;
import lang::typhonql::Script;
import lang::typhonml::XMIReader;

import lang::typhonql::util::Log;

import IO;
import Set;
import List;
import util::Maybe;
import String;

void runDDL(Request r, Schema s, Session session, Log log = noLog) {
	if ((Request) `<Statement stmt>` := r) {
		// TODO This is needed because we do not have an explicit way to distinguish
		// DDL updates from DML updates. Perhaps we should consider it
  		if (isDDL(stmt)) {
  			runUpdate(r, s, session, log = log);
  		}
  		else {
  			throw "DDL statement should have been provided";
  		}
  	}
  	else {
  		throw "Statement should have been provided";
  	}
}

CommandResult runUpdate(Request r, Schema s, Session session, Log log = noLog) {
	if ((Request) `<Statement stmt>` := r) {
		// TODO This is needed because we do not have an explicit way to distinguish
		// DDL updates from DML updates. Perhaps we should consider it
  		if (!isDDL(stmt)) {
  			scr = request2script(r, s, log = log);
			log("[runUpdate] Script: <scr>");
			res = runScript(scr, session, s);
			if (res != "")
				return <-1, ("uuid" : res)>;
			else
				return <-1, ()>;
  		}
  		else {
  			scr = request2script(r, s, log = log);
			log("[runUpdate-DDL] Script: <scr>");
			res = runScript(scr, session, s);
			return <-1, ()>;
  		}
  	}
    throw "Statement should have been provided";
}

void runScriptForQuery(Request r, Schema sch, Session session, Log log = noLog) {
	if ((Request) `from <{Binding ","}+ bs> select <{Result ","}+ selected> <Where? where> <GroupBy? groupBy> <OrderBy? orderBy>` := r) {
		scr = request2script(r, sch, log = log);
		log("[runScriptForQuery] Script: <scr>");
		runScript(scr, session, sch);
	}
	else
		throw "Expected query, given statement";
}

value runQueryAndGetJava(Request r, Schema sch, Session session, Log log = noLog) {
	runScriptForQuery(r, sch, session, log = log);
	return session.getJavaResult();
}

ResultTable runQuery(Request r, Schema sch, Session session, Log log = noLog) {
	runScriptForQuery(r, sch, session, log = log);
	return session.getResult();
}

list[CommandResult] runPrepared(Request req, list[str] columnNames, list[list[str]] values, Schema s, Session session, Log log = noLog) {
  lrel[int, map[str, str]] rs = [];
  int numberOfVars = size(columnNames);
  for (list[str] vs <- values) {
  	map[str, str] labeled = (() | it + (columnNames[i] : vs[i]) | i <-[0 .. numberOfVars]);
  	int i = 0;
  	Request req_ = visit(req) {
  		case (Expr) `<PlaceHolder ph>`: {
  			valStr = labeled["<ph.name>"];
  			e = [Expr] valStr; 
  			insert e;
  		}
  	};
  	<n, uuids> = runUpdate(req_, s, session, log = log);
  	rs += <n, uuids>;
  }
  return rs;
}

void runSchema(Schema sch, Session session, Log log = noLog) {
	scr = schema2script(sch, log = log);
	runScript(scr, session, sch);
}

CommandResult runUpdate(str src, str xmiString, map[str, Connection] connections, Log log = noLog) {
  Session session = newSession(connections, log = log);
  return runUpdate(src, xmiString, session, log = log);
}

CommandResult runUpdate(str src, str xmiString, Session session, Log log = noLog) {
  Model m = xmiString2Model(xmiString);
  Schema s = model2schema(m);
  Request req = [Request]src;
  return runUpdate(req, s, session, log = log);
}

ResultTable runQuery(str src, str xmiString, map[str, Connection] connections, Log log = noLog) {
  Session session = newSession(connections, log = log);
  return runQuery(src, xmiString, session, log = log);
}

ResultTable runQuery(str src, str xmiString, Session session, Log log = noLog) {
  Model m = xmiString2Model(xmiString);
  Schema s = model2schema(m);
  Request req = [Request]src;
  return runQuery(req, s, session, log = log);
}

value runQueryAndGetJava(str src, str xmiString, map[str, Connection] connections, Log log = noLog) {
  Session session = newSession(connections, log = log);
  return runQueryAndGetJava(src, xmiString, session, log = log);
}

value runQueryAndGetJava(str src, str xmiString, Session session, Log log = noLog) {
  Model m = xmiString2Model(xmiString);
  Schema s = model2schema(m);
  Request req = [Request]src;
  return runQueryAndGetJava(req, s, session, log = log);
}

list[CommandResult] runPrepared(str src, list[str] columnNames, list[list[str]] values, str xmiString, Session session, Log log = noLog) {
 	Model m = xmiString2Model(xmiString);
  	Schema s = model2schema(m);	
	return runPrepared([Request] src, columnNames, values, s, session, log = log);
}

list[CommandResult] runPrepared(str src, list[str] columnNames, list[list[str]] values, str xmiString, map[str, Connection] connections, Log log = noLog) {
 	Session session = newSession(connections, log = log);
 	return runPrepared(src, columnNames, values, xmiString, session, log = log);
}

void runDDL(str src,  str xmiString, Session session, Log log = noLog) {
	Model m = xmiString2Model(xmiString);
  	Schema s = model2schema(m);	
	runDDL([Request] src, s, session, log = log);
}

void runDDL(str src,  str xmiString, map[str, Connection] connections, Log log = noLog) {
	Session session = newSession(connections, log = log);
	runDDL(src, xmiString, session, log = log);
}

void runSchema(str xmiString, Session session, Log log = noLog) {
	Model m = xmiString2Model(xmiString);
  	Schema s = model2schema(m);	
	runSchema(s, session, log = log);
}

void runSchema(str xmiString, map[str, Connection] connections, Log log = noLog) {
	Session session = newSession(connections, log = log);
	runSchema(xmiString, session, log = log);
}

Path buildPath(str selector, map[str, str] entityTypes) {
	list[str] parts = split(".", selector);
	str label = parts[0];
	ty = entityTypes[label];
	return <label, ty, parts[1..]>;
}

