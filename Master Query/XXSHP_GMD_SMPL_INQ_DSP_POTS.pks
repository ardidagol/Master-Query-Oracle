CREATE OR REPLACE PACKAGE APPS.XXSHP_GMD_SMPL_INQ_DSP_POTS
IS
   TYPE gmd_smpl_ine_t IS TABLE OF xxshp_gmd_smpl_inq_dsp_lns%ROWTYPE
      INDEX BY PLS_INTEGER;

   TYPE T_SAMPLE IS RECORD
   (
      sample_id              NUMBER,
      spec_id                NUMBER,
      item_id                NUMBER,
      item_code              VARCHAR2 (255),
      item_desc              VARCHAR2 (32756),
      lot_number             VARCHAR2 (255),
      requestor              VARCHAR2 (255),
      sample_creation_date   DATE,
      received_date          DATE,
      days                   NUMBER,
      complete_result_date   DATE,
      disposition            VARCHAR2 (255),
      lab_organization_id    NUMBER,
      organization_id        NUMBER,
      sample_no              VARCHAR2 (255),
      sample_source          VARCHAR2 (255)
   );

   FUNCTION XXSHP_SAMPLE_TEST
      RETURN TYPE_SAMPLE_TEST_TBL
      PIPELINED;

   PROCEDURE insert_to_inq_dsp_line (p_org_id     IN     NUMBER,
                                     p_user_id    IN     NUMBER,
                                     p_login_id   IN     NUMBER,
                                     v_err           OUT NUMBER,
                                     v_msg           OUT VARCHAR2);

   PROCEDURE insert_to_inq_dsp_dtl (p_org_id     IN     NUMBER,
                                    p_user_id    IN     NUMBER,
                                    p_login_id   IN     NUMBER,
                                    v_err           OUT NUMBER,
                                    v_msg           OUT VARCHAR2);

   PROCEDURE insert_to_inq_dsp_line1 (p_org_id     IN     NUMBER,
                                      p_user_id    IN     NUMBER,
                                      p_login_id   IN     NUMBER,
                                      p_result        OUT VARCHAR2);

   PROCEDURE process_data (p_org_id     IN     NUMBER,
                           p_user_id    IN     NUMBER,
                           p_login_id   IN     NUMBER,
                           errbuf          OUT VARCHAR2,
                           retcode         OUT NUMBER);

   PROCEDURE insert_to_stg;
END XXSHP_GMD_SMPL_INQ_DSP_POTS;
/
