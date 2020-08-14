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

package nl.cwi.swat.typhonql.backend.mariadb;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.function.Consumer;
import java.util.function.Supplier;
import java.util.regex.Matcher;

import org.locationtech.jts.geom.Geometry;
import org.locationtech.jts.io.WKBWriter;

import lang.typhonql.util.MakeUUID;
import nl.cwi.swat.typhonql.backend.Binding;
import nl.cwi.swat.typhonql.backend.Engine;
import nl.cwi.swat.typhonql.backend.MultipleBindings;
import nl.cwi.swat.typhonql.backend.QueryExecutor;
import nl.cwi.swat.typhonql.backend.Record;
import nl.cwi.swat.typhonql.backend.ResultIterator;
import nl.cwi.swat.typhonql.backend.ResultStore;
import nl.cwi.swat.typhonql.backend.UpdateExecutor;
import nl.cwi.swat.typhonql.backend.rascal.Path;

public class MariaDBEngine extends Engine {

	private final Supplier<Connection> connection;

	public MariaDBEngine(ResultStore store, List<Consumer<List<Record>>> script, List<Runnable> updates,
			Map<String, List<UUID>> uuids, Supplier<Connection> sqlConnection) {
		super(store, script, updates, uuids);
		this.connection = sqlConnection;
	}

	private PreparedStatement prepareQuery(String query, List<String> vars, Set<String> blobs) throws SQLException {
		Matcher m = QL_PARAMS.matcher(query);
		StringBuffer result = new StringBuffer(query.length());
		while (m.find()) {
			m.appendReplacement(result, "?");
			String param = m.group(1);
			if (param.startsWith("blob-")) {
				param = param.substring("blob-".length());
				blobs.add(param);
			}
			vars.add(param);
		}
		m.appendTail(result);
		String jdbcQuery = result.toString();
		return connection.get().prepareStatement(jdbcQuery);
	}

	private PreparedStatement prepareAndBind(String query, Map<String, Object> values) throws SQLException {
		List<String> vars = new ArrayList<>();
		Set<String> blobs = new HashSet<>();
		PreparedStatement stm = prepareQuery(query, vars, blobs);
		bindInPreparedStatement(stm, values, vars, blobs);
		return stm;
	}

	private void bindInPreparedStatement(PreparedStatement stm, Map<String, Object> values, List<String> vars,
			Set<String> blobs) throws SQLException {
		int i = 1;
		for (String varName : vars) {
			Object value = values.get(varName);
			if (value == null && blobs.contains(varName)) {
				stm.setBlob(i, store.getBlob(varName));
			} else if (value instanceof Geometry) {
				stm.setBytes(i, new WKBWriter().write((Geometry) value));
			} else if (value instanceof UUID) {
				stm.setBytes(i, MakeUUID.uuidToBytes((UUID) value));
			} else {
				// TODO: what to do with NULL?
				// other classes jdbc can take care of itself
				stm.setObject(i, value);
			}
			i++;
		}
	}
	
	public void executeSelect(String resultId, String query, List<Path> signature) {
		executeSelect(resultId, query, new HashMap<String, Binding>(), signature);
	}

	public void executeSelect(String resultId, String query, Map<String, Binding> bindings, List<Path> signature) {
		new QueryExecutor(store, script, uuids, bindings, signature) {
			@Override
			protected ResultIterator performSelect(Map<String, Object> values) {
				try {
					return new MariaDBIterator(prepareAndBind(query, values).executeQuery());
				} catch (SQLException e1) {
					throw new RuntimeException(e1);
				}
			}

		}.executeSelect(resultId);
	}

	public void executeUpdate(String query, Map<String, Binding> bindings, Optional<MultipleBindings> mBindings) {
		new UpdateExecutor(query, store, updates, uuids, bindings, mBindings) {

			@Override
			protected void performUpdate(Map<String, Object> values) {
				try {
					PreparedStatement stm = prepareAndBind(query, values);
					stm.executeUpdate();
				} catch (SQLException e1) {
					throw new RuntimeException(e1);
				}

			}

		}.executeUpdate();
	}
	
}
