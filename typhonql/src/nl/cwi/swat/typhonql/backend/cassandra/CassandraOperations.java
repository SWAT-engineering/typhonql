package nl.cwi.swat.typhonql.backend.cassandra;

import java.net.InetSocketAddress;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.function.BiFunction;
import java.util.function.Consumer;
import java.util.function.Function;
import org.rascalmpl.interpreter.IEvaluatorContext;
import org.rascalmpl.interpreter.result.ICallableValue;
import org.rascalmpl.interpreter.result.Result;
import org.rascalmpl.interpreter.result.ResultFactory;
import org.rascalmpl.interpreter.types.FunctionType;
import com.datastax.oss.driver.api.core.CqlIdentifier;
import com.datastax.oss.driver.api.core.CqlSession;
import com.datastax.oss.driver.api.core.CqlSessionBuilder;
import io.usethesource.vallang.IList;
import io.usethesource.vallang.IMap;
import io.usethesource.vallang.IString;
import io.usethesource.vallang.IValue;
import io.usethesource.vallang.IValueFactory;
import io.usethesource.vallang.type.Type;
import nl.cwi.swat.typhonql.backend.Closables;
import nl.cwi.swat.typhonql.backend.Record;
import nl.cwi.swat.typhonql.backend.ResultStore;
import nl.cwi.swat.typhonql.backend.rascal.ConnectionData;
import nl.cwi.swat.typhonql.backend.rascal.Operations;
import nl.cwi.swat.typhonql.backend.rascal.TyphonSessionState;

public class CassandraOperations  implements Operations, AutoCloseable {
	private final Map<String, ConnectionData> connectionInfo;
	private final Map<String, CqlSession> connections = new HashMap<>();

	public CassandraOperations(Map<String, ConnectionData> connections) {
		this.connectionInfo = connections;
	}
	
	private CqlSession getConnection(String db, boolean global) {
		return connections.computeIfAbsent(global ? "#" + db : db, n -> {
			ConnectionData con = connectionInfo.get(db);
			if (con == null) {
				throw new RuntimeException("Missing connection infor for: " + db);
			}
			CqlSessionBuilder builder = CqlSession.builder();
			builder.addContactPoint(new InetSocketAddress(con.getHost(), con.getPort()));
			if (con.getUser() != null && !con.getUser().isEmpty()) {
				builder.withAuthCredentials(con.getUser(), con.getPassword());
			}
			if (!global) {
				builder.withKeyspace(CqlIdentifier.fromCql("\"" + db + "\""));
			}
			builder.withLocalDatacenter("datacenter1");
			return builder.build();
		});
	}

	public IValue buildOperations(ResultStore store, List<Consumer<List<Record>>> script,
			List<Runnable> updates, TyphonSessionState state, Map<String, String> uuids,
			IEvaluatorContext ctx, IValueFactory vf) {

		Type aliasedTuple = unalias(Objects.requireNonNull(ctx.getCurrentEnvt().lookupAlias("CassandraOperations")));
		BiFunction<String, Function<IValue[], Result<IValue>>, ICallableValue> makeFunc = 
				(ft, bd) -> makeFunction(ctx, state, func(aliasedTuple, ft), bd);

		CassandraEngine engine = new CassandraEngine(store, script, updates, uuids);

		return vf.tuple(
				makeFunc.apply("executeQuery", executeBody(engine)),
				makeFunc.apply("executeStatement", executeStatementBody(engine)),
				makeFunc.apply("executeGlobalStatement", executeGlobalStatementBody(engine))
        );
	}

	private static FunctionType func(Type tp, String name) {
		return (FunctionType) tp.getFieldType(name);
	}

	private static Type unalias(Type aliased) {
		while (aliased.isAliased()) {
			aliased = aliased.getAliased();
		}
		return aliased;
	}
	


	private Function<IValue[], Result<IValue>> executeBody(CassandraEngine engine) {
		return args -> {
			String resultId = ((IString) args[0]).getValue();
			String dbName = ((IString) args[1]).getValue();
			String query = ((IString) args[2]).getValue();
			IMap bindings = (IMap) args[3];
			IList signatureList = (IList) args[4];

			engine.executeSelect(resultId, query, 
					rascalToJavaBindings(bindings), 
					rascalToJavaSignature(signatureList), 
					() -> getConnection(dbName, false));
			return ResultFactory.nothing();
		};
	}
	
	private Function<IValue[], Result<IValue>> executeStatementBody(CassandraEngine engine) {
		return args -> executeUpdate(engine, args, false);
	}

	private Function<IValue[], Result<IValue>> executeGlobalStatementBody(CassandraEngine engine) {
		return args -> executeUpdate(engine, args, true);
	}

	private Result<IValue> executeUpdate(CassandraEngine engine, IValue[] args, boolean global) {
        String dbName = ((IString) args[0]).getValue();
        String query = ((IString) args[1]).getValue();
        IMap bindings = (IMap) args[2];

        engine.executeUpdate(query, rascalToJavaBindings(bindings), () -> getConnection(dbName, global));
        return ResultFactory.nothing();
	}


	@Override
	public void close() throws Exception {
		Closables.autoCloseAll(connections.values(), Exception.class);
	}

}
