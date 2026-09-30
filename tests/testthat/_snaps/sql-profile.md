# SQL wrappers print statements when irelink.show_sql is TRUE

    Code
      il_db_get_query(con, "SELECT 1 AS x", "query")
    Message
      -- query
      SELECT 1 AS x
      
    Output
        x
      1 1

# format_sql() lays out clauses, conditions, and CASE branches

    Code
      cat(format_sql(sql))
    Output
      SELECT COUNT(*) AS n,
        CASE
          WHEN l.x = r.x THEN 1
          ELSE 0 END AS g
      FROM (
        SELECT l.unique_id
        FROM "t" l, "t" r
        WHERE l.unique_id < r.unique_id
          AND l.x = r.x
      ) AS pairs
      LEFT JOIN "tf" ON pairs.x = tf.x
      GROUP BY g

