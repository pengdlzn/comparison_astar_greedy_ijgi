drop function if exists compute_cost_type_change(tbl_name text);
--CREATE OR REPLACE FUNCTION compute_cost_type_change(tbl_name text) RETURNS setof double precision as
CREATE OR REPLACE FUNCTION compute_cost_type_change(tbl_name text) RETURNS double precision AS
    $$
    DECLARE
        total_cost_type_1 double precision := 0;
        total_cost_type_2 double precision := 0;
        last_cost_type_2 double precision := 0;
        current_cost_type_2 double precision := 0;
        current_face_row record;  --e.g., astar_tgap_tgap_face%ROWTYPE
        aggregated_face_row record;  --e.g., astar_tgap_tgap_face%ROWTYPE
        start_face_row record;  --e.g., astar_tgap_tgap_face%ROWTYPE
        type_distance_pre_cur_dbl double precision := 0;
        type_distance_start_pre_dbl double precision := 0;
        type_distance_start_cur_dbl double precision := 0;
        operation_num integer := 0;
        current_step integer := 0;
        test_text text;
        scale_d_squared double precision := 2500000000; --50000 * 50000
        scale_factor double precision;
    BEGIN
        
        EXECUTE format('select max(step_low) from %s', tbl_name) INTO operation_num;
--        RAISE NOTICE 'operation_num = %', operation_num;
        
--        current_step := 9;
--        operation_num := 10;
        
        LOOP
            current_step := current_step + 1;
            scale_factor := scale_d_squared * 5537 /(5537-current_step);
--            scale_factor := 1;
        
            --get current_face_row; there is only one current_face_row
            EXECUTE format('SELECT * from %s 
			WHERE step_low = %s 
                            ORDER BY face_id 
                            LIMIT 1', tbl_name, current_step) 
                            INTO current_face_row;            
--            RAISE NOTICE 'current_face_row = %', current_face_row.feature_class; 
            

            FOR aggregated_face_row IN
                EXECUTE format('SELECT * from %s
                                WHERE step_high = %s', tbl_name, current_step)
            LOOP                
                --get type_distance_pre_cur_dbl
                SELECT distance into type_distance_pre_cur_dbl
                from type_distance
                where type_from = aggregated_face_row.feature_class 
                    and type_to = current_face_row.feature_class;

                total_cost_type_1 := total_cost_type_1 + 
                                    type_distance_pre_cur_dbl * aggregated_face_row.area / scale_factor;                
                
                
                FOR start_face_row in
                    EXECUTE format('SELECT * from %s
                                    WHERE step_low = %s', tbl_name, 0)                
                LOOP
                    IF ST_Contains(aggregated_face_row.geometry, start_face_row.geometry) THEN
                        SELECT distance into type_distance_start_pre_dbl
                        from type_distance
                        where type_from = start_face_row.feature_class 
                            and type_to = aggregated_face_row.feature_class;                        
                        current_cost_type_2 := last_cost_type_2 - 
                                                type_distance_start_pre_dbl * start_face_row.area;
                        
                        
                        SELECT distance into type_distance_start_cur_dbl
                        from type_distance
                        where type_from = start_face_row.feature_class 
                            and type_to = current_face_row.feature_class;                        
                        current_cost_type_2 := current_cost_type_2 + 
                                            type_distance_start_cur_dbl * start_face_row.area;                        
                    END IF;
                END LOOP;                
            END LOOP;
            
            total_cost_type_2 := total_cost_type_2 + current_cost_type_2 / scale_factor;
--            total_cost_type_2 := total_cost_type_2 + current_cost_type_2 / current_step;
            
            last_cost_type_2 = current_cost_type_2;
            EXIT WHEN current_step = operation_num;  --operation_num=4803 for buchholz with A*
        END LOOP;
        
        total_cost_type_1 := total_cost_type_1/3;
--        select to_char(total_cost_type_1 + total_cost_type_2, '999999999999999999999.9') into test_text;
--        RAISE notice '% = %', rpad('total_cost_type', 20, ' '), test_text;
        select to_char(total_cost_type_1, '999999999999999999999.9999999999') into test_text;
        RAISE notice '% = %', rpad('total_cost_type_1', 20, ' '), test_text;
--        select to_char(total_cost_type_2, '999999999999999999999.9') into test_text;
--        RAISE notice '% = %', rpad('total_cost_type_2', 20, ' '), test_text;


--        return next total_cost_type_1 + total_cost_type_2;
        return total_cost_type_1;
    END;
    $$ LANGUAGE plpgsql;

drop function if exists compute_cost_length_change(tbl_name text);    
CREATE OR REPLACE FUNCTION compute_cost_length_change(tbl_name text) RETURNS double precision AS 
    $$
    declare
        total_cost_length double precision := 0;
        total_cost_length_1 double precision := 0;
        total_cost_length_2 double precision := 0;
        last_interior_length double precision := 0;
        current_interior_length double precision := 0;
        length_decrease_start double precision := 0;
        length_diff double precision := 0;
        length_diff_1 double precision := 0;
        length_diff_2 double precision := 0;
        edge_row record;
        operation_num integer := 0;
        current_step integer := 0;
        n_state integer := 0;
        test_text text;
        scale_d_squared double precision := 2500000000; --50000 * 50000
        scale_factor double precision;        
    BEGIN
        
        EXECUTE format('select max(step_low) from %s', tbl_name) INTO operation_num;
        n_state := operation_num + 1;
        
--        current_step := 9;
--        operation_num := 10;
        
        --compute current_interior_length
        FOR edge_row IN
            EXECUTE format('SELECT * from %s
                            WHERE step_low = 0 
                              and (left_face_id_low != 0 and right_face_id_low != 0)', tbl_name)
        loop            
            current_interior_length := current_interior_length + st_length(edge_row.geometry);
        END LOOP;
--        RAISE notice 'current_interior_length = %', current_interior_length;
        length_decrease_start := current_interior_length / operation_num;

        
        LOOP
               current_step := current_step + 1;
            scale_factor := scale_d_squared * 5537 /(5537-current_step);
--            scale_factor := 1;
               last_interior_length := current_interior_length;
               current_interior_length := 0;

       
            FOR edge_row IN
                EXECUTE format('SELECT * from %s
                                WHERE (step_low <= %s and step_high > %s) 
                                  and (left_face_id_low != 0 and right_face_id_low != 0)', 
                                         tbl_name, current_step, current_step)
            loop            
                current_interior_length := current_interior_length + st_length(edge_row.geometry);
            END LOOP;
            length_diff := last_interior_length - current_interior_length;
            length_diff_1 := last_interior_length - current_interior_length 
                                - last_interior_length / (n_state - current_step + 1);
            length_diff_2 := last_interior_length - current_interior_length - length_decrease_start;      
            
            total_cost_length := total_cost_length + length_diff * length_diff / scale_factor;
            total_cost_length_1 := total_cost_length_1 + length_diff_1 * length_diff_1 / scale_factor;    
            total_cost_length_2 := total_cost_length_2 + length_diff_2 * length_diff_2 / scale_factor;

     
            EXIT WHEN current_step = operation_num;  --operation_num=4803 for buchholz with A*
            
        END LOOP;
        

        select to_char(total_cost_length, '999999999999999999999.9999999999') into test_text;
        RAISE notice '% = %', rpad('total_cost_leng', 20, ' '), test_text;    
    
--        select to_char(total_cost_length_1 + total_cost_length_2, '999999999999999999999.9') into test_text;
--        RAISE notice '% = %', rpad('total_cost_leng', 20, ' '), test_text;
--        select to_char(total_cost_length_1, '999999999999999999999.9') into test_text;
--        RAISE notice '% = %', rpad('total_cost_leng_1', 20, ' '), test_text;
--        select to_char(total_cost_length_2, '999999999999999999999.9') into test_text;
--        RAISE notice '% = %', rpad('total_cost_leng_2', 20, ' '), test_text;
        
--        RAISE notice '% total_cost_length = %', tbl_name, total_cost_length_1 + total_cost_length_2;
--        RAISE notice '% total_cost_length_1 = %', tbl_name, total_cost_length_1;        
--        RAISE notice '% total_cost_length_2 = %', tbl_name, total_cost_length_2;        


        return total_cost_length;
    END;
    $$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION compute_cost() RETURNS setof double precision AS 
    $$
    declare
		total_cost double precision := 0;
        total_cost_greedy double precision := 0;
        total_cost_astar double precision := 0;
        mycost double precision := 0; 
        test_text text;
    begin
--        RAISE notice '';
--        RAISE notice '';   
        RAISE notice '========================== GREEDY ===============================';
        total_cost_greedy := compute_cost_type_change('greedy_tgap_tgap_face') 
                            + compute_cost_length_change('greedy_tgap_tgap_edge');
        select to_char(total_cost_greedy, '999999999999999999999.9') into test_text;
        RAISE notice '% = %', rpad('total_cost', 20, ' '), test_text;
        return next total_cost_greedy;
        
        RAISE notice '';
        RAISE notice '========================== ASTAR ================================';
        total_cost_astar := compute_cost_type_change('astar_tgap_tgap_face') 
                            + compute_cost_length_change('astar_tgap_tgap_edge');
        select to_char(total_cost_astar, '999999999999999999999.9') into test_text;
        RAISE notice '% = %', rpad('total_cost', 20, ' '), test_text;
        return next total_cost_astar;
    END;
    $$ LANGUAGE plpgsql;
    

SELECT * FROM compute_cost();
--SELECT * FROM compute_cost_type_change('greedy_tgap_tgap_face');
