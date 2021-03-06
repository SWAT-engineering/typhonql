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

package nl.cwi.swat.typhonql.backend.rascal;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Objects;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Consumer;
import java.util.stream.Collectors;

import org.rascalmpl.interpreter.IEvaluatorContext;
import org.rascalmpl.interpreter.env.ModuleEnvironment;
import org.rascalmpl.interpreter.result.ICallableValue;
import org.rascalmpl.interpreter.result.ResultFactory;
import org.rascalmpl.interpreter.types.FunctionType;
import org.rascalmpl.interpreter.utils.RuntimeExceptionFactory;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import io.usethesource.vallang.IConstructor;
import io.usethesource.vallang.IInteger;
import io.usethesource.vallang.IList;
import io.usethesource.vallang.IListWriter;
import io.usethesource.vallang.IMap;
import io.usethesource.vallang.IString;
import io.usethesource.vallang.ITuple;
import io.usethesource.vallang.IValue;
import io.usethesource.vallang.IValueFactory;
import io.usethesource.vallang.type.Type;
import io.usethesource.vallang.type.TypeFactory;
import nl.cwi.swat.typhonql.backend.ExternalArguments;
import nl.cwi.swat.typhonql.backend.Record;
import nl.cwi.swat.typhonql.backend.ResultStore;
import nl.cwi.swat.typhonql.backend.Runner;
import nl.cwi.swat.typhonql.backend.cassandra.CassandraOperations;
import nl.cwi.swat.typhonql.backend.mariadb.MariaDBOperations;
import nl.cwi.swat.typhonql.backend.mongodb.MongoOperations;
import nl.cwi.swat.typhonql.backend.neo4j.Neo4JOperations;
import nl.cwi.swat.typhonql.backend.nlp.NlpOperations;
import nl.cwi.swat.typhonql.client.DatabaseInfo;
import nl.cwi.swat.typhonql.client.XMIPolystoreConnection;
import nl.cwi.swat.typhonql.client.resulttable.ResultTable;

public class TyphonSession implements Operations {

	private static final Logger logger = LoggerFactory.getLogger(TyphonSession.class);
	private static final TypeFactory TF = TypeFactory.getInstance();
	private final IValueFactory vf;

	public TyphonSession(IValueFactory vf) {
		this.vf = vf;
	}
	
	private String[] toStringArray(IList varNames) {
		Iterator<IValue> iter = varNames.iterator();
		List<String> ss = new ArrayList<String>();
		while (iter.hasNext()) {
			ss.add(((IString)iter.next()).getValue());
		}
		return ss.toArray(new String[0]);
	}
	
	private String[][] toStringMatrix(IList values) {
		Iterator<IValue> iter = values.iterator();
		List<Object[]> ss = new ArrayList<Object[]>();
		while (iter.hasNext()) {
			ss.add(toStringArray((IList) iter.next()));
		}
		return ss.toArray(new String[0][]);
	}

	public ITuple newSession(IMap connections, IMap fileMap, IEvaluatorContext ctx) {
		return newSessionWrapper(connections, translateBlobMap(fileMap), Optional.empty(), ctx).getTuple();
	}
	
	public ITuple newSessionWithArguments(IMap connections, IList columnNames, IList columnTypes,
			IList values, IMap fileMap, IEvaluatorContext ctx) {
		Map<String, InputStream> blobMap = translateBlobMap(fileMap);
		ExternalArguments externalArguments =
				XMIPolystoreConnection.buildExternalArguments(
						toStringArray(columnNames),
						toStringArray(columnTypes),
						toStringMatrix(values), blobMap, true);
		return newSessionWrapper(connections, blobMap, Optional.of(externalArguments), ctx).getTuple();
	}
	
	public SessionWrapper newSessionWrapper(IMap connections, Map<String, InputStream> blobMap, Optional<ExternalArguments> externalArguments,
			IEvaluatorContext ctx) {
		Map<String, ConnectionData> mariaDbConnections = new HashMap<>();
		Map<String, ConnectionData> mongoConnections = new HashMap<>();
		Map<String, ConnectionData> cassandraConnections = new HashMap<>();
		Map<String, ConnectionData> neoConnections = new HashMap<>();
		Map<String, ConnectionData> nlpConnections = new HashMap<>();

		Iterator<Entry<IValue, IValue>> connIter = connections.entryIterator();

		while (connIter.hasNext()) {
			Entry<IValue, IValue> entry = connIter.next();
			String dbName = ((IString) entry.getKey()).getValue();
			IConstructor cons = (IConstructor) entry.getValue();
			String host = ((IString) cons.get("host")).getValue();
			int port = ((IInteger) cons.get("port")).intValue();
			String user = ((IString) cons.get("user")).getValue();
			String password = ((IString) cons.get("password")).getValue();
			ConnectionData data = new ConnectionData(host, port, user, password);
			switch (cons.getName()) {
				case "mariaConnection":
					mariaDbConnections.put(dbName, data);
					break;
				case "mongoConnection":
                    mongoConnections.put(dbName, data);
                    break;
				case "cassandraConnection":
                    cassandraConnections.put(dbName, data);
                    break;
				case "neoConnection":
                    neoConnections.put(dbName, data);
                    break; 
				case "nlpConnection":
                    nlpConnections.put(dbName, data);
                    break; 
			}
		}
		return newSessionWrapper(mariaDbConnections, mongoConnections, cassandraConnections, neoConnections, nlpConnections, blobMap, externalArguments, ctx);
	}

	private Map<String, InputStream> translateBlobMap(IMap blobMap) {
		Map<String, InputStream> actualBlobMap = new HashMap<>();
		Iterator<Entry<IValue, IValue>> it = blobMap.entryIterator();
		while (it.hasNext()) {
			Entry<IValue, IValue> cur = it.next();
			String key = ((IString)cur.getKey()).getValue();
			String value = ((IString)cur.getValue()).getValue();
			actualBlobMap.put(key, new ByteArrayInputStream(value.getBytes(StandardCharsets.UTF_8)));
		}
		return actualBlobMap;
	}

	public SessionWrapper newSessionWrapper(List<DatabaseInfo> connections, Map<String, InputStream> blobMap, Optional<ExternalArguments> externalArguments, IEvaluatorContext ctx) {
		Map<String, ConnectionData> mariaDbConnections = new HashMap<>();
		Map<String, ConnectionData> mongoConnections = new HashMap<>();
		Map<String, ConnectionData> cassandraConnections = new HashMap<>();
		Map<String, ConnectionData> neoConnections = new HashMap<>();
		Map<String, ConnectionData> nlpConnections = new HashMap<>();
		for (DatabaseInfo db : connections) {
			switch (db.getDbms().toLowerCase()) {
			case "mongodb":
				mongoConnections.put(db.getDbName(), new ConnectionData(db));
				break;
			case "mariadb":
				mariaDbConnections.put(db.getDbName(), new ConnectionData(db));
				break;
			case "cassandra":
				cassandraConnections.put(db.getDbName(), new ConnectionData(db));
				break;
			case "neo4j":
				neoConnections.put(db.getDbName(), new ConnectionData(db));
				break;
			case "nlae":
				nlpConnections.put(db.getDbName(), new ConnectionData(db));
				break;
			default:
				throw new RuntimeException("Missing type: " + db.getDbms());
			}
		}
		return newSessionWrapper(mariaDbConnections, mongoConnections, cassandraConnections, neoConnections, nlpConnections, blobMap, externalArguments, ctx);
	}

	private SessionWrapper newSessionWrapper(Map<String, ConnectionData> mariaDbConnections,
			Map<String, ConnectionData> mongoConnections, Map<String, ConnectionData> cassandraConnections, 
			Map<String, ConnectionData> neoConnections, Map<String, ConnectionData> nlpConnections, Map<String, InputStream> blobMap, 
			Optional<ExternalArguments> externalArguments, IEvaluatorContext ctx) {
		// checkIsNotInitialized();
		// borrow the type store from the module, so we don't have to build the function
		// type ourself
		if (blobMap == null) {
			blobMap = Collections.emptyMap();
		}
		ModuleEnvironment aliasModule = ctx.getHeap().getModule("lang::typhonql::Session");
		if (aliasModule == null) {
			throw new IllegalArgumentException("Missing my own module");
		}
		Type aliasedTuple = Objects.requireNonNull(ctx.getCurrentEnvt().lookupAlias("Session"));
		while (aliasedTuple.isAliased()) {
			aliasedTuple = aliasedTuple.getAliased();
		}

		// get the function types
		FunctionType getResultType = (FunctionType) aliasedTuple.getFieldType("getResult");
		FunctionType getJavaResultType = (FunctionType) aliasedTuple.getFieldType("getJavaResult");
		FunctionType readAndStoreType = (FunctionType) aliasedTuple.getFieldType("readAndStore");
		FunctionType doneType = (FunctionType) aliasedTuple.getFieldType("finish");
		FunctionType closeType = (FunctionType) aliasedTuple.getFieldType("done");
		FunctionType newIdType = (FunctionType) aliasedTuple.getFieldType("newId");
		FunctionType javaCall = (FunctionType) aliasedTuple.getFieldType("javaReadAndStore");
		FunctionType hasAnyExternalArgumentsType = (FunctionType) aliasedTuple.getFieldType("hasAnyExternalArguments");
		FunctionType hasMoreExternalArgumentsType = (FunctionType) aliasedTuple.getFieldType("hasMoreExternalArguments");
		FunctionType nextExternalArgumentsType = (FunctionType) aliasedTuple.getFieldType("nextExternalArguments");
		FunctionType reportType = (FunctionType) aliasedTuple.getFieldType("report");

		// construct the session tuple
		ResultStore store = new ResultStore(blobMap, externalArguments);
		Map<String, UUID> uuids = new HashMap<>();
		List<Consumer<List<Record>>> script = new ArrayList<>();
		TyphonSessionState state = new TyphonSessionState();

		MariaDBOperations mariaDBOperations = new MariaDBOperations(mariaDbConnections);
		MongoOperations mongoOperations = new MongoOperations(mongoConnections);
		CassandraOperations cassandra = new CassandraOperations(cassandraConnections);
		Neo4JOperations neo = new Neo4JOperations(neoConnections);
		NlpOperations nlp = new NlpOperations(nlpConnections);
		state.addOpperations(mariaDBOperations);
		state.addOpperations(mongoOperations);
		state.addOpperations(cassandra);
		state.addOpperations(neo);
		state.addOpperations(nlp);
		
		return new SessionWrapper(vf.tuple(makeGetResult(state, getResultType, ctx),
				makeGetJavaResult(state, getJavaResultType, ctx),
				makeReadAndStore(store, script, state, readAndStoreType, ctx),
				makeJavaReadAndStore(store, script, state, uuids, ctx, javaCall),
				makeFinish(script, state, doneType, ctx),
				makeClose(store, state, closeType, ctx),
				makeNewId(uuids, state, newIdType, ctx),
				makeHasAnyExternalArguments(store, state, hasAnyExternalArgumentsType, ctx),
				makeHasMoreExternalArguments(store, state, hasMoreExternalArgumentsType, ctx),
				makeNextExternalArguments(store, state, nextExternalArgumentsType, ctx),
				makeReport(state, reportType, ctx),
				mariaDBOperations.newSQLOperations(store, script, state, uuids, ctx, vf),
				mongoOperations.newMongoOperations(store, script, state, uuids, ctx, vf),
				cassandra.buildOperations(store, script, state, uuids, ctx, vf),
				neo.newNeo4JOperations(store, script, state, uuids, ctx, vf),
				nlp.newNlpOperations(store, script, state, uuids, ctx, vf)
				), state);
	}

	private IValue makeHasAnyExternalArguments(ResultStore store, TyphonSessionState state, FunctionType hasAnyExternalArgumentsType,
			IEvaluatorContext ctx) {
		return makeFunction(ctx, state, hasAnyExternalArgumentsType, args -> {
			return ResultFactory.makeResult(TF.boolType(), vf.bool(store.hasExternalArguments()), ctx);
		});
	}
	
	private IValue makeHasMoreExternalArguments(ResultStore store, TyphonSessionState state, FunctionType hasMoreExternalArgumentsType,
			IEvaluatorContext ctx) {
		return makeFunction(ctx, state, hasMoreExternalArgumentsType, args -> {
			return ResultFactory.makeResult(TF.boolType(), vf.bool(store.hasMoreExternalArguments()), ctx);
		});
	}
	
	private IValue makeNextExternalArguments(ResultStore store, TyphonSessionState state, FunctionType nextExternalArgumentsType,
			IEvaluatorContext ctx) {
		return makeFunction(ctx, state, nextExternalArgumentsType, args -> {
			store.nextExternalArguments();
			if (!store.hasMoreExternalArguments()) {
				// we are done iterating over arguments, so let's flush all
				state.flush();
			}
			return ResultFactory.makeResult(TF.voidType(), null, ctx);
		});
	}

	private IValue makeNewId(Map<String, UUID> uuids, TyphonSessionState state, FunctionType newIdType,
			IEvaluatorContext ctx) {
		return makeFunction(ctx, state, newIdType, args -> {
			String idName = ((IString) args[0]).getValue();
			UUID uuid = UUID.randomUUID();
			uuids.put(idName, uuid);
			return ResultFactory.makeResult(TF.stringType(), vf.string(uuid.toString()), ctx);
		});
	}

	private ICallableValue makeClose(ResultStore store, TyphonSessionState state, FunctionType closeType,
			IEvaluatorContext ctx) {
		return makeFunction(ctx, state, closeType, args -> {
			close(state);
			return ResultFactory.makeResult(TF.voidType(), null, ctx);
		});
	}
	
	private static List<Path> compilePaths(IList pathsList) {
		List<Path> paths = new ArrayList<>();
		for (IValue v: pathsList) {
			paths.add(toPath((ITuple)v));
		}
		return paths;
	}

	private ResultTable computeResultTable(ResultStore store, List<Consumer<List<Record>>> script, IValue[] args) {
		try {
			return Runner.computeResultTable(script, compilePaths((IList) args[0]));
		} catch (RuntimeException e) {
			throw RuntimeExceptionFactory.javaException(e, null, null);
		}
	}

	private ICallableValue makeGetResult(TyphonSessionState state, FunctionType getResultType,
			IEvaluatorContext ctx) {
		return makeFunction(ctx, state, getResultType, args -> {
			// alias ResultTable = tuple[list[str] columnNames, list[list[value]] values];
			try (ByteArrayOutputStream json = new ByteArrayOutputStream()) {
				state.getResult().serializeJSON(json);
                return ResultFactory.makeResult(
                        TF.tupleType(new Type[] { TF.listType(TF.stringType()), TF.listType(TF.listType(TF.valueType())) },
                                new String[] { "columnNames", "values" }),
                        parseTable(json.toByteArray()), ctx);
			} catch (IOException e) {
				throw new RuntimeException(e);
			}
		});
	}
	
	private ICallableValue makeReport(TyphonSessionState state, FunctionType funcType,
			IEvaluatorContext ctx) {
		return makeFunction(ctx, state, funcType, args -> {
			state.addWarnings(((IString)args[0]).getValue());
			return ResultFactory.nothing();
		});
	}

	private IValue parseTable(byte[] json) {
		try {
			ObjectMapper objectMapper = new ObjectMapper();
			JsonNode tbl = objectMapper.readTree(json);
			JsonNode columns = tbl.get("columnNames");
			if (columns == null || !columns.isArray()) {
				throw new RuntimeException("Incorrect result table json");
			}
			IListWriter columnList = vf.listWriter();
			columns.iterator().forEachRemaining(c -> columnList.append(vf.string(c.asText())));

			IListWriter valueList = vf.listWriter();
			tbl.get("values").iterator().forEachRemaining(row -> {
				IListWriter rowList = vf.listWriter();
				row.iterator().forEachRemaining(c -> rowList.append(toIValue(c)));
				valueList.append(rowList.done());
			});
			return vf.tuple(columnList.done(), valueList.done());
		} catch (IOException e) {
			throw new RuntimeException(e);
		}
	}

	private IValue toIValue(JsonNode c) {
		if (c.isNumber()) {
			if (c.canConvertToInt()) {
				return vf.integer(c.asInt());
			}
			return vf.real(c.asDouble());
		}
		else if (c.isBoolean()) {
			return vf.bool(c.asBoolean());
		}
		else if (c.isNull()) {
			return vf.set();
		}
		else if (c.isTextual()) {
			return vf.string(c.asText());
		}
		else if (c.isArray()) {
			IListWriter lst = vf.listWriter();
			c.elements().forEachRemaining(x -> lst.append(toIValue(x)));
			return lst.done();
		}
		else {
			throw new RuntimeException("Cannot convert " + c + " into an IValue");
		}
	}

	private ICallableValue makeGetJavaResult(TyphonSessionState state, FunctionType getResultType,
			IEvaluatorContext ctx) {
		return makeFunction(ctx, state, getResultType, args -> {
			return ResultFactory.makeResult(TF.externalType(TF.valueType()), state.getResult(), ctx);
		});
	}

	private ICallableValue makeReadAndStore(ResultStore store, List<Consumer<List<Record>>> script,
			TyphonSessionState state, FunctionType readAndStoreType, IEvaluatorContext ctx) {
		return makeFunction(ctx, state, readAndStoreType, args -> {
			logger.debug("Running {} prepared steps", script.size());
			ResultTable rt = computeResultTable(store, script, args);
			state.setResult(rt);
			script.clear();
			return ResultFactory.makeResult(TF.voidType(), null, ctx);
		});
	}

	private ICallableValue makeFinish(List<Consumer<List<Record>>> script, TyphonSessionState state,
			FunctionType readAndStoreType, IEvaluatorContext ctx) {
		return makeFunction(ctx, state, readAndStoreType, args -> {
			logger.debug("Running {} prepared steps", script.size());
			Runner.executeUpdates(script);
			script.clear();
			return ResultFactory.makeResult(TF.voidType(), null, ctx);
		});
	}

	private IValue makeJavaReadAndStore(ResultStore store, List<Consumer<List<Record>>> script, 
			TyphonSessionState state, Map<String, UUID> uuids, IEvaluatorContext ctx, FunctionType javaCall) {
		return makeFunction(ctx, state, javaCall, args -> {
			logger.debug("Running {} prepared steps", script.size());
			List<Path> paths = compilePaths((IList)args[2]);
			List<String> columnNames = ((IList)args[3]).stream().map(v -> ((IString)v).getValue()).collect(Collectors.toList());
			JavaOperation.compileAndAggregate(store, state, script, uuids, ((IString)args[0]).getValue(), ((IString)args[1]).getValue(), paths, columnNames);
			return ResultFactory.makeResult(TF.voidType(), null, ctx);
		});
	}

	private static Path toPath(ITuple path) {
		IList pathLst = (IList) path.get(3);
		Iterator<IValue> vs = pathLst.iterator();
		List<String> fields = new ArrayList<String>();
		while (vs.hasNext()) {
			fields.add(((IString) (vs.next())).getValue());
		}
		String dbName = ((IString) path.get(0)).getValue();
		String var = ((IString) path.get(1)).getValue();
		String entityType = ((IString) path.get(2)).getValue();
		return new Path(dbName, var, entityType, fields.toArray(new String[0]));
	}

	public void close(TyphonSessionState state) {
		try {
			state.close();
		} catch (Exception e) {
			if (e instanceof RuntimeException) {
				throw (RuntimeException)e;
			}
			throw new RuntimeException("Failure to close state", e);
		}

	}

}
