---
layout: ../layouts/GistLayout.astro
tags: [database]
---

# Postgres - integration through triggers and jobs

We can use the excellent `listen` and `notify` feature of Postgres to keep data in a table in database in sync with table in another database.

1. Define a trigger on the table we need to keep in sync.
    
    ```sql
    CREATE FUNCTION record_created() RETURNS trigger AS $$
    BEGIN
    	PERFORM graphile_worker.add_job('record_created', row_to_json(NEW));
    	RETURN NEW;
    END;
    $$ LANGUAGE plpgsql VOLATILE;
    
    CREATE TRIGGER my_table_trigger AFTER INSERT ON my_table FOR EACH ROW EXECUTE PROCEDURE record_created();
    ```
    
2. The above code inserts a job record with newly inserted record as data for `nodejs` `graphile_worker` job processor that processes the jobs as desired.
