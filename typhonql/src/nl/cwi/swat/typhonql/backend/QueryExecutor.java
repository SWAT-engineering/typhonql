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

package nl.cwi.swat.typhonql.backend;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;
import java.util.UUID;
import java.util.function.Consumer;

import nl.cwi.swat.typhonql.backend.rascal.Path;

public abstract class QueryExecutor {
	
	private ResultStore store;
	private List<Consumer<List<Record>>> script;
	private Map<String, Binding> bindings;
	private Map<Binding, String> inverseBindings;
	private Map<String, UUID> uuids;
	private List<Path> signature;

	public QueryExecutor(ResultStore store, List<Consumer<List<Record>>> script, Map<String, UUID> uuids, Map<String, Binding> bindings, List<Path> signature) {
		this.store = store;
		this.script = script;
		this.bindings = bindings;
		this.uuids = uuids;
		this.signature = signature;
		this.inverseBindings = new HashMap<Binding, String>();
		for (Entry<String, Binding> e : bindings.entrySet()) {
			inverseBindings.put(e.getValue(), e.getKey());
		}
	}
	
	public void executeSelect(String resultId) {
		executeSelect(resultId, -1);
	}
	
	public void executeSelect(String resultId, int argumentsPointer) {
		int nxt = script.size() + 1;
	    script.add((List<Record> rows) -> {
	    	if (rows.size() <= 1) {
               ResultIterator iter = executeSelect( rows.size() == 0 ? new HashMap<>(): bind(rows.get(0)), argumentsPointer);
               storeResults(resultId, iter);
               processResults(script.get(nxt), rows, iter);
	    	}
	    	else {
                List<ResultIterator> results = new ArrayList<>(rows.size());
                for (Record record : rows) {
                   ResultIterator iter = executeSelect(bind(record), argumentsPointer);
                   results.add(iter);
                   processResults(script.get(nxt), rows, iter);
                }
                storeResults(resultId, new AggregatedResultIterator(results));
	    	}
	    });
	}

	private void processResults(Consumer<List<Record>> consumer, List<Record> rows, ResultIterator iter) {
		while (iter.hasNextResult()) {
		      iter.nextResult();
		      Record r = iter.buildRecord(signature);
		      List<Record> newRow = horizontalAdd(rows, r);
		      consumer.accept(newRow);
		   }
	}
	
	
	private Map<String, Object> bind(Record record) {
		Map<String, Object> values = new HashMap<String, Object>();
        for (Field f : record.getObjects().keySet()) {
            if (inverseBindings.containsKey(f)) {
                String var = inverseBindings.get(f);
                values.put(var, record.getObject(f));
            }
        }
		return values;
	}
	
	private List<Record> horizontalAdd(List<Record> rows, Record r) {
		List<Record> result = new ArrayList<Record>();
		if (!rows.isEmpty()) { 
			for (Record row : rows) {
				result.add(horizontalAdd(row, r));
			}
			return result;
		}
		else
			return Arrays.asList(r);
	}

	private Record horizontalAdd(Record row, Record r) {
		Map<Field, Object> map = new HashMap<>();
		map.putAll(row.getObjects());
		map.putAll(r.getObjects());
		return new Record(map);
	}
	
	protected abstract ResultIterator performSelect(Map<String, Object> values);
	
	private ResultIterator executeSelect(Map<String, Object> values, int argumentsPointer) {
		if (values.size() == bindings.size()) {
			if (argumentsPointer != -1) {
				values.putAll(store.getExternalArguments(argumentsPointer));
			}
			return performSelect(values); 
		}
		else {
			String var = bindings.keySet().iterator().next();
			Binding binding = bindings.get(var);
			if (binding instanceof Field) {
				List<ResultIterator> lst = new ArrayList<>();
				Field field = (Field) binding;
				ResultIterator results =  store.getResults(field.getReference());
				results.beforeFirst();
				while (results.hasNextResult()) {
					results.nextResult();
					Object value = (field.getAttribute().equals("@id"))? results.getCurrentId(field.getLabel(), field.getType()) : results.getCurrentField(field.getLabel(), field.getType(), field.getAttribute());
					values.put(var, value);
					lst.add(executeSelect(values, argumentsPointer));
				}
				return new AggregatedResultIterator(lst);
			}
			else {
				GeneratedIdentifier id = (GeneratedIdentifier) binding;
				values.put(id.getName(), uuids.get(id.getName()));
				return executeSelect(values, argumentsPointer);
			}
			
		}
	}
	
	protected void storeResults(String resultId, ResultIterator results) {
		store.put(resultId,  results);
	}

}
