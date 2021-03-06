-- This file follows procedure signatures of split_nquads.sql, making the files interchangeable.

-- Translate raw input into RDF-patch formatted N-Quads; subdivide N-Quads over graph iri, buffer N-Quads up to
-- maxq per graph iri, output N-Quads per graph when maxq has been reached.
--
-- This strategy keeps quads in vectors per graph in a dict, until maxq for a vector/graph has been reached.
-- disadvantage: Virtuoso runs out of memory.
CREATE PROCEDURE vql_buffer_nquad(IN op ANY, IN raw_s ANY, IN raw_p ANY, IN raw_o ANY, IN raw_g ANY,
        IN buffer ANY, IN report ANY, IN at_checkpoint VARCHAR, IN maxq INT := 100000) {

    DECLARE qline, g_name, g_iri VARCHAR;
    DECLARE g_vector ANY;

    -- increase quad count in report
    dict_inc_or_put(report, 'quad_count', 1);

    g_iri := __ro2sq(raw_g);
    qline := vql_create_nquad(op, raw_s, raw_p, raw_o, raw_g);
    g_name := encode_base64(g_iri);

    g_vector := dict_get(buffer, g_name); -- g_vector may be <DB NULL>
    g_vector := vector_concat(g_vector, vector(qline)); -- vector_concat: first parameter may be <DB NULL>
    -- dbg_printf('VQL: Added to graph vector %s quad %s', g_iri, qline);
    if (length(g_vector) >= maxq) {
        vql_print_graph(g_name, g_vector, at_checkpoint, report);
        g_vector := vector();
    }
    dict_put(buffer, g_name, g_vector);
}


CREATE PROCEDURE vql_print_buffer(IN buffer ANY, IN report ANY, IN at_checkpoint VARCHAR) {

    DECLARE g_name, g_vector ANY;

    dict_iter_rewind (buffer);
    while (dict_iter_next (buffer, g_name, g_vector)) {
        vql_print_graph(g_name, g_vector, at_checkpoint, report);
    }
}


CREATE PROCEDURE vql_print_graph(IN g_name STRING, IN g_vector ANY, IN at_checkpoint VARCHAR, IN report ANY) {

    DECLARE len, j INT;
    DECLARE g_iri VARCHAR;

    len := length(g_vector);
    if (len > 0) {
        g_iri := decode_base64(g_name);
        dbg_printf('VQL: Exporting %d N-Quads from graph %s', len, g_iri);
        -- increase file count in report
        dict_inc_or_put(report, 'file_count', 1);
        -- header
        result(concat('# at checkpoint  ', at_checkpoint));
        result(concat('# graph          ', g_iri));
        result(concat('# base64         ', g_name));
        result(concat('# amount         ', len));
        for (j := 0; j < len; j := j + 1) {
            result(g_vector[j]);
        }
    }
}