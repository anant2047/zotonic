.. _cookbook-custom-pivots:

Custom pivots
=============

:ref:`guide-datamodel-query-model` can only sort and filter on
:ref:`resources <guide-datamodel-resources>` that actually have a database
column. Zotonic's resources are stored in a serialized form. This
allows you to very easily add any property to any resource but
you cannot sort or filter on them until you make database columns
for these properties.

The way to take this on is using the "custom pivot" feature. A custom
pivot table is an extra database table with columns in which the props
you define are copied, so you can filter and sort on them.

Say you want to sort on a property of the resource called ``requestor``.

Create (and export!) an ``init/1`` function in your site where you define a custom pivot table::

    init(Context) ->
        z_pivot_rsc:define_custom_pivot(pivotname, [{requestor, "varchar(80)"}], Context),
        ok.

The new table will be called ``pivot_<pivotname>``. When you change the column
names in the table definition, the table will be recreated and **the data inside will be lost**.

To fill the pivot table with data when a resource gets saved, create a notification
listener function ``observe_custom_pivot/2``::

    observe_custom_pivot(#custom_pivot{ id = Id }, Context) ->
        Requestor = m_rsc:p(Id, requestor, Context),
        {pivotname, [{requestor, Requestor}]}.

This will fill the 'requestor' property for every entry in your
database, when the resource is pivoted.

Recompile your site and restart it (so the ``init`` function is called)
and then in the admin under ‘System’ -> ‘Status’ choose ‘Rebuild
search indexes’. This will gradually fill the new pivot table. Enable
the logging module and choose "log" in the admin menu to see the pivot
progress. Once the table is filled, you can use the pivot table to do
sorting and filtering.

To sort on 'requestor', do the following:

.. code-block:: django

    {% with m.search.paged[{query cat='foo' sort='pivot.pivotname.requestor'}] as result %}

Or you can filter on it:

.. code-block:: django

  {% with m.search.paged[{query filter=["pivot.pivotname.requestor", `=`, "hello"]}]
     as result %}

.. seealso::

    * :ref:`custompivot` search argument for filtering on custom pivot columns.
    * :ref:`cookbook-pivot-templates` to change the content of regular pivot columns and search texts.
