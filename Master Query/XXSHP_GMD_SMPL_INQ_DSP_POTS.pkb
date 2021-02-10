/* Formatted on 3/2/2020 4:17:49 PM (QP5 v5.256.13226.35538) */
CREATE OR REPLACE PACKAGE BODY APPS.XXSHP_GMD_SMPL_INQ_DSP_POTS
IS
   FUNCTION XXSHP_SAMPLE_TEST
      RETURN TYPE_SAMPLE_TEST_TBL
      PIPELINED
   IS
      v_rec   TYPE_SAMPLE_TEST_TBL := TYPE_SAMPLE_TEST_TBL ();
   BEGIN
      SELECT TYPE_SAMPLE_TEST (sample_id,
                               spec_id,
                               item_id,
                               item_code,
                               item_desc,
                               lot_number,
                               requestor,
                               sample_creation_date,
                               received_date,
                               days,
                               complete_result_date,
                               disposition,
                               lab_organization_id,
                               organization_id,
                               sample_no,
                               sample_source)
        BULK COLLECT INTO v_rec
        FROM (  SELECT lns.sample_id,
                       gesd.spec_id,
                       (SELECT inventory_item_id
                          FROM gmd_samples
                         WHERE sample_id = lns.sample_id)
                          item_id,
                       (SELECT segment1
                          FROM mtl_system_items_b
                         WHERE     inventory_item_id = lns.inventory_item_id
                               AND organization_id = lns.organization_id)
                          item_code,
                       (SELECT description
                          FROM mtl_system_items_b
                         WHERE     inventory_item_id = lns.inventory_item_id
                               AND organization_id = lns.organization_id)
                          item_desc,
                       lns.lot_number,
                       gs.attribute23 requestor,
                       gs.creation_date sample_creation_date,
                       gs.date_received received_date,
                       MAX (TO_NUMBER (NVL (gqt.attribute2, 0))) days,
                       CAST (NULL AS DATE) complete_result_date,
                       gss.disposition,
                       gr.lab_organization_id,
                       hdr.organization_id,
                       gs.sample_no,
                       xxshp_gmd_sample_analysis_pkg.get_sample_source (
                          lns.sample_id)
                          sample_source
                  FROM gmd_samples gs,
                       xxshp_gmd_smpl_crt_lns lns,
                       xxshp_gmd_smpl_crt_hdr hdr,
                       xxshp_gmd_smpl_crt_test sct,
                       gmd_results gr,
                       gmd_spec_results gsr,
                       gmd_sample_spec_disp gss,
                       gmd_event_spec_disp gesd,
                       gmd_qc_tests gqt,
                       gmd_test_classes gtc,
                       gmd_test_methods gtm,
                       gmd_spec_tests gst
                 WHERE     1 = 1
                       AND gs.sample_id = lns.sample_id
                       AND hdr.sample_hdr_id = lns.sample_hdr_id
                       AND gs.sample_id = gr.sample_id
                       AND gs.sampling_event_id = gesd.sampling_event_id
                       AND (   gsr.evaluation_ind <> '5O'
                            OR gsr.evaluation_ind IS NULL)
                       AND gs.sample_id = gss.sample_id
                       AND gqt.test_id = gr.test_id
                       AND gr.result_id = gsr.result_id
                       AND gst.spec_id = lns.spec_id
                       AND gst.test_id = sct.test_id
                       AND gsr.event_spec_disp_id = gesd.event_spec_disp_id
                       AND gqt.test_class = gtc.test_class
                       AND gtm.test_method_id = gqt.test_method_id
                       AND lns.sample_line_id = sct.sample_line_id
                       AND gqt.test_id = sct.test_id
                       AND NOT EXISTS
                                  (SELECT 1
                                     FROM xxshp_gmd_smpl_inq_dsp_lns dsp_ln
                                    WHERE     1 = 1 --dsp_dtl.line_id = lns.sample_line_id
                                          AND dsp_ln.sample_id = lns.sample_id)
              --         AND lns.sample_hdr_id = 229
              GROUP BY lns.sample_id,
                       gesd.spec_id,
                       lns.lot_number,
                       gs.attribute23,
                       gs.creation_date,
                       gs.date_received,
                       gss.disposition,
                       gr.lab_organization_id,
                       hdr.organization_id,
                       gs.sample_no,
                       lns.inventory_item_id,
                       lns.organization_id
              ORDER BY item_code, sample_no, lot_number);

      FOR i IN 1 .. v_rec.COUNT
      LOOP
         PIPE ROW (v_rec (i));
      END LOOP;

      RETURN;
   END;


   PROCEDURE insert_to_inq_dsp_line (p_org_id     IN     NUMBER,
                                     p_user_id    IN     NUMBER,
                                     p_login_id   IN     NUMBER,
                                     v_err           OUT NUMBER,
                                     v_msg           OUT VARCHAR2)
   IS
      v_line_cnt   NUMBER := 0;
      v_date       DATE;
      v_val        NUMBER;
   --v_rec        gmd_smpl_ine_t := gmd_smpl_ine_t ();
   BEGIN
      FOR j IN (SELECT sample_id,
                       spec_id,
                       item_id,
                       lot_number,
                       requestor,
                       sample_creation_date,
                       received_date,
                       days,
                       complete_result_date,
                       disposition,
                       organization_id,
                       item_code,
                       sample_no,
                       sample_source
                  FROM XXSHP_GMD_SMPL_INQ_DSP_CRT_V
                 WHERE ORGANIZATION_ID = p_org_id AND ROWNUM <= 100)
      LOOP
         v_line_cnt := v_line_cnt + 1;

         SELECT MAX (gr.result_date)
           INTO v_date
           FROM gmd_samples gs,
                xxshp_gmd_smpl_crt_lns lns,
                xxshp_gmd_smpl_crt_hdr hdr,
                xxshp_gmd_smpl_crt_test sct,
                gmd_results gr,
                gmd_spec_results gsr,
                gmd_sample_spec_disp gss,
                gmd_event_spec_disp gesd,
                gmd_qc_tests gqt,
                gmd_test_classes gtc,
                gmd_test_methods gtm,
                gmd_spec_tests gst
          WHERE     1 = 1
                AND gs.sample_id = lns.sample_id
                AND hdr.sample_hdr_id = lns.sample_hdr_id
                AND gs.sample_id = gr.sample_id
                AND gs.sampling_event_id = gesd.sampling_event_id
                AND (gsr.evaluation_ind <> '5O' OR gsr.evaluation_ind IS NULL)
                AND gs.sample_id = gr.sample_id
                AND gs.sample_id = gss.sample_id
                AND gqt.test_id = gr.test_id
                AND gr.result_id = gsr.result_id
                AND gst.spec_id = gesd.spec_id
                AND gst.test_id = sct.test_id
                AND gsr.event_spec_disp_id = gesd.event_spec_disp_id
                AND gqt.test_class = gtc.test_class
                AND gtm.test_method_id = gqt.test_method_id
                AND lns.sample_line_id = sct.sample_line_id
                AND gqt.test_id = sct.test_id
                AND lns.organization_id = p_org_id
                AND lns.sample_id = j.sample_id;


         SELECT COUNT (1)
           INTO v_val
           FROM xxshp_gmd_smpl_inq_dsp_lns
          WHERE     1 = 1
                AND sample_id = j.sample_id
                AND sample_source = j.sample_source;


         IF (v_val = 0)
         THEN
            INSERT INTO xxshp_gmd_smpl_inq_dsp_lns (line_num,
                                                    sample_source,
                                                    sample_id,
                                                    spec_id,
                                                    item_id,
                                                    lot_number,
                                                    requestor,
                                                    sample_creation_date,
                                                    received_date,
                                                    days,
                                                    complete_result_date,
                                                    --disposition, --get from gmd_sample_spec_disp
                                                    organization_id,
                                                    created_by,
                                                    creation_date,
                                                    last_updated_by,
                                                    last_update_date,
                                                    last_update_login)
                 VALUES (v_line_cnt,
                         j.sample_source,
                         j.sample_id,
                         j.spec_id,
                         j.item_id,
                         j.lot_number,
                         j.requestor,
                         j.sample_creation_date,
                         j.received_date,
                         j.days,
                         v_date,
                         --j.disposition,  --get from gmd_sample_spec_disp
                         j.organization_id,
                         p_user_id,
                         SYSDATE,
                         p_user_id,
                         SYSDATE,
                         p_login_id);

            COMMIT;
         END IF;
      END LOOP;
   EXCEPTION
      WHEN OTHERS
      THEN
         v_msg :=
            'Failed when insert into xxshp_gmd_smpl_inq_dsp_lns, ' || SQLERRM;
         v_err := 1;
         ROLLBACK;
   END insert_to_inq_dsp_line;

   PROCEDURE insert_to_inq_dsp_line1 (p_org_id     IN     NUMBER,
                                      p_user_id    IN     NUMBER,
                                      p_login_id   IN     NUMBER,
                                      p_result        OUT VARCHAR2)
   AS
      --      v_curr_trx_number   VARCHAR2 (100);
      --      v_sum_invoice       NUMBER;
      v_line_cnt   NUMBER := 0;
      v_date       DATE;
      v_val        NUMBER;

      CURSOR cur_sample
      IS
         SELECT sample_id,
                spec_id,
                item_id,
                lot_number,
                requestor,
                sample_creation_date,
                received_date,
                days,
                complete_result_date,
                disposition,
                organization_id,
                item_code,
                sample_no,
                sample_source
           FROM XXSHP_GMD_SMPL_INQ_DSP_CRT_V
          WHERE ORGANIZATION_ID = p_org_id;

      TYPE lT_sample IS TABLE OF cur_sample%ROWTYPE;

      l_sample     lt_sample;
   BEGIN
      OPEN cur_sample;

      LOOP
         FETCH cur_sample BULK COLLECT INTO l_sample LIMIT 500;

         EXIT WHEN l_sample.COUNT = 0;

         FOR idx IN 1 .. l_sample.COUNT
         LOOP
            v_line_cnt := v_line_cnt + 1;

            SELECT MAX (gr.result_date)
              INTO v_date
              FROM gmd_samples gs,
                   xxshp_gmd_smpl_crt_lns lns,
                   xxshp_gmd_smpl_crt_hdr hdr,
                   xxshp_gmd_smpl_crt_test sct,
                   gmd_results gr,
                   gmd_spec_results gsr,
                   gmd_sample_spec_disp gss,
                   gmd_event_spec_disp gesd,
                   gmd_qc_tests gqt,
                   gmd_test_classes gtc,
                   gmd_test_methods gtm,
                   gmd_spec_tests gst
             WHERE     1 = 1
                   AND gs.sample_id = lns.sample_id
                   AND hdr.sample_hdr_id = lns.sample_hdr_id
                   AND gs.sample_id = gr.sample_id
                   AND gs.sampling_event_id = gesd.sampling_event_id
                   AND (   gsr.evaluation_ind <> '5O'
                        OR gsr.evaluation_ind IS NULL)
                   AND gs.sample_id = gr.sample_id
                   AND gs.sample_id = gss.sample_id
                   AND gqt.test_id = gr.test_id
                   AND gr.result_id = gsr.result_id
                   AND gst.spec_id = gesd.spec_id
                   AND gst.test_id = sct.test_id
                   AND gsr.event_spec_disp_id = gesd.event_spec_disp_id
                   AND gqt.test_class = gtc.test_class
                   AND gtm.test_method_id = gqt.test_method_id
                   AND lns.sample_line_id = sct.sample_line_id
                   AND gqt.test_id = sct.test_id
                   AND lns.organization_id = p_org_id
                   AND lns.sample_id = l_sample (idx).sample_id;


            SELECT COUNT (1)
              INTO v_val
              FROM xxshp_gmd_smpl_inq_dsp_lns
             WHERE     1 = 1
                   AND sample_id = l_sample (idx).sample_id
                   AND sample_source = l_sample (idx).sample_source;


            IF (v_val = 0)
            THEN
               INSERT INTO xxshp_gmd_smpl_inq_dsp_lns (line_num,
                                                       sample_source,
                                                       sample_id,
                                                       spec_id,
                                                       item_id,
                                                       lot_number,
                                                       requestor,
                                                       sample_creation_date,
                                                       received_date,
                                                       days,
                                                       complete_result_date,
                                                       --disposition, --get from gmd_sample_spec_disp
                                                       organization_id,
                                                       created_by,
                                                       creation_date,
                                                       last_updated_by,
                                                       last_update_date,
                                                       last_update_login)
                    VALUES (v_line_cnt,
                            l_sample (idx).sample_source,
                            l_sample (idx).sample_id,
                            l_sample (idx).spec_id,
                            l_sample (idx).item_id,
                            l_sample (idx).lot_number,
                            l_sample (idx).requestor,
                            l_sample (idx).sample_creation_date,
                            l_sample (idx).received_date,
                            l_sample (idx).days,
                            v_date,
                            l_sample (idx).organization_id,
                            p_user_id,
                            SYSDATE,
                            p_user_id,
                            SYSDATE,
                            p_login_id);
            END IF;
         END LOOP;
      END LOOP;

      COMMIT;
      P_RESULT := 'Sukses';
   EXCEPTION
      WHEN OTHERS
      THEN
         ROLLBACK;
         P_RESULT := SQLERRM;
         DBMS_OUTPUT.put_line (P_RESULT);
   END insert_to_inq_dsp_line1;

   PROCEDURE insert_to_inq_dsp_dtl (p_org_id     IN     NUMBER,
                                    p_user_id    IN     NUMBER,
                                    p_login_id   IN     NUMBER,
                                    v_err           OUT NUMBER,
                                    v_msg           OUT VARCHAR2)
   IS
   BEGIN
      INSERT INTO xxshp_gmd_smpl_inq_dsp_dtls (dtl_num,
                                               line_id,
                                               test_id,
                                               test_code,
                                               test_method_id,
                                               test_class,
                                               result_id,
                                               --result_value,evaluation_ind,target_value,min_value,max_value,
                                               organization_id,
                                               created_by,
                                               creation_date,
                                               last_updated_by,
                                               last_update_date,
                                               last_update_login)
         SELECT ROWNUM dtl_num,
                idl.line_id,
                gqt.test_id,
                gqt.test_code,
                gtm.test_method_id,
                gqt.test_class,
                gr.result_id,
                --nvl(gr.RESULT_VALUE_CHAR, to_char(gr.RESULT_VALUE_NUM)) result_value, gsr.EVALUATION_IND,
                --gst.TARGET_VALUE_CHAR target_value, gst.MIN_VALUE_NUM min_value, gst.MAX_VALUE_NUM max_value,
                lns.organization_id,
                p_user_id,
                SYSDATE,
                p_user_id,
                SYSDATE,
                p_login_id
           FROM gmd_samples gs,
                xxshp_gmd_smpl_crt_lns lns,
                xxshp_gmd_smpl_crt_hdr hdr,
                xxshp_gmd_smpl_inq_dsp_lns idl,
                xxshp_gmd_smpl_crt_test sct,
                gmd_results gr,
                gmd_spec_results gsr,
                gmd_sample_spec_disp gss,
                gmd_event_spec_disp gesd,
                gmd_qc_tests gqt,
                gmd_test_classes gtc,
                gmd_test_methods gtm,
                gmd_spec_tests gst
          WHERE     1 = 1
                AND gs.sample_id = lns.sample_id
                AND hdr.sample_hdr_id = lns.sample_hdr_id
                AND gs.sample_id = gr.sample_id
                AND gs.sampling_event_id = gesd.sampling_event_id
                AND (gsr.evaluation_ind <> '5O' OR gsr.evaluation_ind IS NULL)
                AND gs.sample_id = gr.sample_id
                AND gs.sample_id = gss.sample_id
                AND idl.sample_id = lns.sample_id
                AND gqt.test_id = gr.test_id
                AND gr.result_id = gsr.result_id
                AND gst.spec_id = gesd.spec_id
                AND gst.test_id = sct.test_id
                AND gsr.event_spec_disp_id = gesd.event_spec_disp_id
                AND gqt.test_class = gtc.test_class
                AND gtm.test_method_id = gqt.test_method_id
                AND lns.sample_line_id = sct.sample_line_id
                AND gqt.test_id = sct.test_id
                AND lns.organization_id = p_org_id
                AND NOT EXISTS
                           (SELECT 1
                              FROM xxshp_gmd_smpl_inq_dsp_dtls dsp_dtl
                             WHERE     dsp_dtl.line_id = idl.line_id
                                   AND dsp_dtl.test_id = gqt.test_id);

      COMMIT;
   EXCEPTION
      WHEN OTHERS
      THEN
         v_msg :=
            'Failed when insert into xxshp_gmd_smpl_inq_dsp_dtls ' || SQLERRM;
         v_err := 1;
         ROLLBACK;
   END insert_to_inq_dsp_dtl;

   PROCEDURE process_data (p_org_id     IN     NUMBER,
                           p_user_id    IN     NUMBER,
                           p_login_id   IN     NUMBER,
                           errbuf          OUT VARCHAR2,
                           retcode         OUT NUMBER)
   IS
      l_err      NUMBER;
      l_msg      VARCHAR2 (1000);
      l_result   VARCHAR2 (1000);
   BEGIN
      insert_to_inq_dsp_line1 (p_org_id,
                               p_user_id,
                               p_login_id,
                               l_result);

      insert_to_inq_dsp_dtl (p_org_id,
                             p_user_id,
                             p_login_id,
                             l_err,
                             l_msg);
   END;

   PROCEDURE insert_to_stg
   IS
   BEGIN
      --INSERT INTO XXSHP_GMD_SMPL_INQ_DSP_LNS_STG
      --SELECT * FROM TABLE (XXSHP_GMD_SMPL_INQ_DSP_PKG.GMD_SMPL_INQ_DSP_V);
      --select * from XXSHP_GMD_SMPL_INQ_DSP_LNS_STG;
      NULL;
      COMMIT;
   END insert_to_stg;

   PROCEDURE type_jalanin_donk
   AS
      a   NUMBER;
   BEGIN
      NULL;
   --DROP TYPE APPS.TYPE_SAMPLE_TEST_TBL;
   --
   --CREATE OR REPLACE TYPE APPS.TYPE_SAMPLE_TEST_TBL IS TABLE OF TYPE_SAMPLE_TEST;
   --
   --DROP TYPE APPS.TYPE_SAMPLE_TEST;
   --
   --CREATE OR REPLACE TYPE APPS.TYPE_SAMPLE_TEST IS OBJECT
   --(
   --   sample_id NUMBER,
   --   spec_id NUMBER,
   --   item_id NUMBER,
   --   item_code VARCHAR2 (255),
   --   item_desc VARCHAR2 (32756),
   --   lot_number VARCHAR2 (255),
   --   requestor VARCHAR2 (255),
   --   sample_creation_date DATE,
   --   received_date DATE,
   --   days NUMBER,
   --   complete_result_date DATE,
   --   disposition VARCHAR2 (255),
   --   lab_organization_id NUMBER,
   --   organization_id NUMBER,
   --   sample_no VARCHAR2 (255),
   --   sample_source VARCHAR2 (255)
   --);
   
   
   END;
END XXSHP_GMD_SMPL_INQ_DSP_POTS;
/