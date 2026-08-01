INSERT INTO workspace_items(name)
SELECT 'TenderHeart workspace ready'
WHERE NOT EXISTS (SELECT 1 FROM workspace_items);
