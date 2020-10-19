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

package engineering.swat.typhonql.client.test;

import java.io.IOException;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.Collections;

import nl.cwi.swat.typhonql.client.CommandResult;
import nl.cwi.swat.typhonql.client.DatabaseInfo;
import nl.cwi.swat.typhonql.client.XMIPolystoreConnection;
import nl.cwi.swat.typhonql.client.resulttable.ResultTable;

public class XMIBasedTyphonQLClientTest3PreparedStatements {
	public static void main(String[] args) throws IOException, URISyntaxException {
		DatabaseInfo[] infos = new DatabaseInfo[] {
				new DatabaseInfo("localhost", 27017, "Reviews", "mongodb", "mongodb",
						"admin", "admin"),
				new DatabaseInfo("localhost", 3306, "Inventory", "mariadb", "mariadb",
						"root", "example") };
		/*
		if (args == null || args.length != 1 && args[0] == null) {
			System.out.println("Provide XMI file name");
			System.exit(-1);
		}
		*/
			
		String fileName = "file:///Users/pablo/git/typhonql/typhonql/src/lang/typhonml/user-review-product-bio.tmlx";
		
		String xmiString = String.join("\n", Files.readAllLines(Paths.get(new URI(fileName))));

		XMIPolystoreConnection conn = new XMIPolystoreConnection();
		
		CommandResult[] crs = conn.executePreparedUpdate(xmiString, Arrays.asList(infos), Collections.emptyMap(), "insert \n" + 
				"	Product {name: ??name, description: ??description }", 
				new String[]{"description", "name"}, 
				new String[][]{ { "\"Best beer\"", "\"Omer\""}, { "\"Good IPA\"", "\"Jopen IPA\""}});
		
		for (CommandResult cr : crs) {
			for (String objLabel : cr.getCreatedUuids().keySet()) {
				System.out.println(objLabel + " -> " + cr.getCreatedUuids().get(objLabel));
			}
		}
		System.out.println("COMMAND RESULTS");
		for (CommandResult cr : crs)
			System.out.println(cr);
		System.out.println("END COMMAND RESULTS");
		
		
		ResultTable iv = conn.executeQuery(xmiString, Arrays.asList(infos),"from Product p select p.name");
		System.out.println("RESULT TABLE");
		System.out.println(iv.toString());
		
	}
}