package nl.cwi.swat.typhonql.backend;

import java.sql.ResultSet;
import java.sql.SQLException;

public class SQLResultIterator implements ResultIterator {

	private ResultSet rs;

	public SQLResultIterator(ResultSet rs) {
		this.rs = rs;
	}

	@Override
	public void nextResult() {
		try {
			rs.next();
		} catch (SQLException e) {
			throw new RuntimeException(e);
		}

	}

	@Override
	public boolean hasNextResult() {
		try {
			return !rs.isLast();
		} catch (SQLException e) {
			throw new RuntimeException(e);
		}
	}

	@Override
	public String getCurrentId(String type) {
		try {
			return rs.getString(type + ".@id");
		} catch (SQLException e) {
			throw new RuntimeException(e);
		}
	}

	@Override
	public Object getCurrentField(String type, String name) {
		try {
			return rs.getObject(type + "." + name);
		} catch (SQLException e) {
			throw new RuntimeException(e);
		}
	}

	@Override
	public void beforeFirst() {
		try {
			rs.beforeFirst();
		} catch (SQLException e) {
			throw new RuntimeException(e);
		}
	}

}
