insert item ke table master_item

item_code = 1 category = direct.im.all.all
item toll = 3/2 category = 
item unstandart = 3/2

CREATE OR REPLACE PACKAGE BODY APPS.xxshp_inv_master_item_reg_pkg
/* $Header: XXSHP_INV_MASTER_ITEM_REG_PKG.pkb 122.5.1.0 2017/02/22 10:41:10 Edi Yanto $ */
AS
   /******************************************************************************
       NAME: xxshp_inv_master_item_reg_pkg
       PURPOSE:

       REVISIONS:
       Ver         Date            Author                Description
       ---------   ----------      ---------------       ------------------------------------
       1.0         14-Mar-2017      Edi Yanto           1. Created this package.
       1.1        12-Oct-2017      Reza Fajrin         1. Update get_post_processing, submit_items_interface
      ******************************************************************************/

   PROCEDURE logf (p_msg IN VARCHAR2)
   AS
   BEGIN
      fnd_file.put_line (fnd_file.LOG, p_msg);
   --DBMS_OUTPUT.put_line (p_msg);
   END logf;

   PROCEDURE outf (p_msg IN VARCHAR2)
   AS
   BEGIN
      fnd_file.put_line (fnd_file.output, p_msg);
   --DBMS_OUTPUT.put_line (p_msg);
   END outf;

   FUNCTION get_post_processing (p_post_Processing VARCHAR2, p_template_id NUMBER)
      RETURN NUMBER
   IS
      v_return   NUMBER;
      v_val      NUMBER;
   BEGIN
      SELECT COUNT (1)
        INTO v_val
        FROM mtl_item_templates
       WHERE template_id = p_template_id AND template_name IN ('RM', 'PM', 'BASE BUY','FGSA DUMMY');

      IF (v_val > 0)
      THEN
         BEGIN
            SELECT TO_NUMBER (description)
              INTO v_return
              FROM fnd_lookup_values
             WHERE     lookup_type = 'XXSHP_LEAD_TIME_RELEASE_PERIO'
                   AND enabled_flag = 'Y'
                   AND lookup_code = p_post_processing;
         EXCEPTION
            WHEN OTHERS
            THEN
               v_return := -1;
         END;
      ELSE
         v_return := 0;
      END IF;

      RETURN v_return;
   EXCEPTION
      WHEN OTHERS
      THEN
         RETURN 0;
   END get_post_processing;


   FUNCTION get_status_desc (p_status VARCHAR2)
      RETURN VARCHAR2
   IS
      p_return   VARCHAR2 (50);
   BEGIN
      SELECT meaning
        INTO p_return
        FROM fnd_lookup_values flv, fnd_application fa
       WHERE     flv.view_application_id = fa.application_id
             AND fa.application_short_name = 'XXSHP'
             AND flv.lookup_type = 'XXSHP_INV_ITEM_REG_STATUS'
             AND flv.enabled_flag = 'Y'
             AND flv.lookup_code = p_status;

      RETURN p_return;
   EXCEPTION
      WHEN OTHERS
      THEN
         RETURN 'error get lookup status ' || SQLERRM;
   END get_status_desc;

   PROCEDURE waitforrequest (request_id IN NUMBER, status OUT VARCHAR2, err_message OUT VARCHAR2)
   IS
      v_result      BOOLEAN;
      v_phase       VARCHAR2 (20);
      v_devphase    VARCHAR2 (20);
      v_devstatus   VARCHAR2 (20);
   BEGIN
      v_result :=
         fnd_concurrent.wait_for_request (request_id,
                                          5,
                                          0,
                                          v_phase,
                                          status,
                                          v_devphase,
                                          v_devstatus,
                                          err_message);
   END waitforrequest;

   PROCEDURE create_uom_conversion (p_reg_hdr_id IN NUMBER)
   /*
        Created by EY on 14-Mar-2017

        History Update:
   */
   IS
      x_return_status   VARCHAR2 (200);
      v_msg_data        VARCHAR2 (2000);
      v_split_kn_flag   VARCHAR2 (1);
      v_item_id         NUMBER;
      v_item_code       mtl_system_items_kfv.concatenated_segments%TYPE;
      v_validate        NUMBER;

      CURSOR cur
      IS
         SELECT inter.ROWID rid,
                'INTER' TYPE,
                inter.from_uom_code,
                inter.to_uom_code,
                inter.conversion_rate
           FROM xxshp_inv_uom_inter_conv inter
          WHERE inter.reg_hdr_id = p_reg_hdr_id
         UNION
         SELECT intra.ROWID rid,
                'INTRA' TYPE,
                intra.to_uom_code from_uom_code,
                intra.from_uom_code to_uom_code,
                intra.conversion_rate
           FROM xxshp_inv_uom_intra_conv intra
          WHERE intra.reg_hdr_id = p_reg_hdr_id;
   BEGIN
      fnd_global.apps_initialize (g_user_id, g_resp_id, g_resp_appl_id);

      SELECT COUNT (1)
        INTO v_validate
        FROM (SELECT *
                FROM xxshp_inv_master_item_reg
               WHERE     SPLIT_KN_FLAG = 'N'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND NVL (status_iface_uom_conv, 'E') = 'E'
              UNION ALL
              SELECT *
                FROM xxshp_inv_master_item_reg reg
               WHERE     SPLIT_KN_FLAG = 'Y'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND EXISTS
                            (SELECT 1
                               FROM xxshp_inv_master_item_kn kn
                              WHERE     NVL (status_iface_uom_conv, 'E') = 'E'
                                    AND kn.reg_hdr_id = reg.reg_hdr_id));


      IF (v_validate = 0)
      THEN
         logf ('No row to process');
      ELSE
         SELECT NVL (split_kn_flag, 'N'), item_id, item_code
           INTO v_split_kn_flag, v_item_id, v_item_code
           FROM xxshp_inv_master_item_reg
          WHERE reg_hdr_id = p_reg_hdr_id;

         IF v_split_kn_flag = 'N'
         THEN
            IF v_item_id IS NOT NULL
            THEN
               FOR c IN cur
               LOOP
                  inv_convert.create_uom_conversion (p_from_uom_code   => c.from_uom_code,
                                                     p_to_uom_code     => c.to_uom_code,
                                                     p_item_id         => v_item_id, --c.inventory_item_id,
                                                     p_uom_rate        => c.conversion_rate,
                                                     x_return_status   => x_return_status);

                  IF x_return_status = 'S'
                  THEN
                     v_msg_data := 'Conversion Created Sucessfully.';
                  ELSIF x_return_status = 'W'
                  THEN
                     v_msg_data := 'Conversion Already Exists.';
                  ELSIF x_return_status = 'U'
                  THEN
                     v_msg_data := 'Unexpected Error Occured.';
                  ELSIF x_return_status = 'E'
                  THEN
                     LOOP
                        v_msg_data := fnd_msg_pub.get (fnd_msg_pub.g_next, fnd_api.g_false);

                        IF v_msg_data IS NULL
                        THEN
                           EXIT;
                        END IF;

                        v_msg_data := v_msg_data || v_msg_data;
                        logf (' --> Message: ' || v_msg_data);
                     END LOOP;
                  END IF;

                  logf (
                        'Item Code '
                     || v_item_code
                     || ' # From UOM '
                     || c.from_uom_code
                     || ' # To UOM '
                     || c.to_uom_code
                     || ' # Rate '
                     || c.conversion_rate
                     || ' : '
                     || v_msg_data);

                  IF c.TYPE = 'INTER'
                  THEN
                     UPDATE xxshp_inv_uom_inter_conv
                        SET status = x_return_status,
                            MESSAGE = 'Item Code ' || v_item_code || ': ' || v_msg_data,
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE ROWID = c.rid;
                  ELSE
                     UPDATE xxshp_inv_uom_intra_conv
                        SET status = x_return_status,
                            MESSAGE = 'Item Code ' || v_item_code || ': ' || v_msg_data,
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE ROWID = c.rid;
                  END IF;
               END LOOP;

               UPDATE xxshp_inv_master_item_reg
                  SET status_iface_uom_conv = 'P' /*Processed
                                                  */
                                                 ,
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE reg_hdr_id = p_reg_hdr_id;
            ELSE
               UPDATE xxshp_inv_master_item_reg
                  SET status_iface_uom_conv = 'E',
                      message_iface_uom_conv = 'Item is not found.',
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE reg_hdr_id = p_reg_hdr_id;
            END IF;
         ELSE
            /* Pecah KN
            */
            FOR ckn IN (SELECT *
                          FROM xxshp_inv_master_item_kn kn
                         WHERE kn.reg_hdr_id = p_reg_hdr_id AND kn.item_id IS NOT NULL)
            LOOP
               FOR c IN cur
               LOOP
                  inv_convert.create_uom_conversion (p_from_uom_code   => c.from_uom_code,
                                                     p_to_uom_code     => c.to_uom_code,
                                                     p_item_id         => ckn.item_id, --c.inventory_item_id,
                                                     p_uom_rate        => c.conversion_rate,
                                                     x_return_status   => x_return_status);

                  IF x_return_status = 'S'
                  THEN
                     v_msg_data := 'Conversion Created Sucessfully.';
                  ELSIF x_return_status = 'W'
                  THEN
                     v_msg_data := 'Conversion Already Exists.';
                  ELSIF x_return_status = 'U'
                  THEN
                     v_msg_data := 'Unexpected Error Occured.';
                  ELSIF x_return_status = 'E'
                  THEN
                     LOOP
                        v_msg_data := fnd_msg_pub.get (fnd_msg_pub.g_next, fnd_api.g_false);

                        IF v_msg_data IS NULL
                        THEN
                           EXIT;
                        END IF;

                        v_msg_data := v_msg_data || v_msg_data;
                        logf (' --> Message: ' || v_msg_data);
                     END LOOP;
                  END IF;

                  logf (
                        'Item Code '
                     || ckn.item_code
                     || ' # From UOM '
                     || c.from_uom_code
                     || ' # To UOM '
                     || c.to_uom_code
                     || ' # Rate '
                     || c.conversion_rate
                     || ' : '
                     || v_msg_data);

                  IF c.TYPE = 'INTER'
                  THEN
                     UPDATE xxshp_inv_uom_inter_conv
                        SET MESSAGE =
                               SUBSTR (
                                  LTRIM (
                                        MESSAGE
                                     || CHR (10)
                                     || 'Item Code '
                                     || v_item_code
                                     || ': '
                                     || v_msg_data,
                                     CHR (10)),
                                  1,
                                  2000),
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE ROWID = c.rid;
                  ELSE
                     UPDATE xxshp_inv_uom_intra_conv
                        SET MESSAGE =
                               SUBSTR (
                                  LTRIM (
                                        MESSAGE
                                     || CHR (10)
                                     || 'Item Code '
                                     || v_item_code
                                     || ': '
                                     || v_msg_data,
                                     CHR (10)),
                                  1,
                                  2000),
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE ROWID = c.rid;
                  END IF;
               END LOOP;

               UPDATE xxshp_inv_master_item_kn
                  SET status_iface_uom_conv = 'P' /* Processed
                                                  */
                                                 ,
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE kn_id = ckn.kn_id;
            END LOOP;
         END IF;


         COMMIT;
      END IF;
   EXCEPTION
      WHEN OTHERS
      THEN
         logf ('Error on create_uom_conversion: ' || SQLERRM);
   END create_uom_conversion;

   PROCEDURE create_asl_attributes (p_reg_hdr_id IN NUMBER)
   /*
        Created by EY on 15-Mar-2017

        History Update:
   */
   IS
      x_record_unique   BOOLEAN;
      v_asl_id          NUMBER;
      v_failed          NUMBER := 0;
      v_success         NUMBER := 0;
      v_item_id         NUMBER;
      v_split_kn_flag   VARCHAR2 (1);
      v_item_code       mtl_system_items_kfv.concatenated_segments%TYPE;
      v_supply_type     xxshp_inv_master_item_reg.supply_type%TYPE;
      v_validate        NUMBER;

      CURSOR cur_asl
      IS
         SELECT asl.ROWID rid, asl.*
           FROM xxshp_po_asl_attributes asl
          WHERE reg_hdr_id = p_reg_hdr_id;
   BEGIN
      SELECT COUNT (1)
        INTO v_validate
        FROM (SELECT *
                FROM xxshp_inv_master_item_reg
               WHERE     SPLIT_KN_FLAG = 'N'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND NVL (status_iface_asl, 'E') = 'E'
              UNION ALL
              SELECT *
                FROM xxshp_inv_master_item_reg reg
               WHERE     SPLIT_KN_FLAG = 'Y'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND EXISTS
                            (SELECT 1
                               FROM xxshp_inv_master_item_kn kn
                              WHERE     NVL (status_iface_asl, 'E') = 'E'
                                    AND kn.reg_hdr_id = reg.reg_hdr_id));


      IF (v_validate = 0)
      THEN
         logf ('No row to process');
      ELSE
         SELECT NVL (split_kn_flag, 'N'),
                item_id,
                item_code,
                supply_type
           INTO v_split_kn_flag,
                v_item_id,
                v_item_code,
                v_supply_type
           FROM xxshp_inv_master_item_reg
          WHERE reg_hdr_id = p_reg_hdr_id;

         --IF v_supply_type IN ('BUY', 'MAKE')
         --THEN
         IF v_split_kn_flag = 'N'
         THEN
            IF v_item_id IS NOT NULL
            THEN
               FOR c IN cur_asl
               LOOP
                  x_record_unique :=
                     po_asl_sv.check_record_unique (NULL,
                                                    c.vendor_id,
                                                    c.vendor_site_id,
                                                    v_item_id,
                                                    NULL,
                                                    -1);

                  IF NOT x_record_unique
                  THEN
                     UPDATE xxshp_po_asl_attributes
                        SET status = 'E',
                            MESSAGE =
                               'Duplicate Supplier/Supplier Site being defined for Item/Commodity.'
                      WHERE ROWID = c.rid;

                     v_failed := v_failed + 1;
                  ELSE
                     SELECT po_approved_supplier_list_s.NEXTVAL INTO v_asl_id FROM DUAL;

                     logf ('Inserting asl_id: ' || v_asl_id);

                     INSERT INTO po_approved_supplier_list (asl_id,
                                                            using_organization_id,
                                                            owning_organization_id,
                                                            vendor_business_type,
                                                            asl_status_id,
                                                            last_update_date,
                                                            last_updated_by,
                                                            creation_date,
                                                            created_by,
                                                            vendor_id,
                                                            item_id,
                                                            vendor_site_id,
                                                            attribute2,
                                                            attribute6,
                                                            attribute8,
                                                            attribute9,
                                                            attribute10,
                                                            attribute11,
                                                            attribute13,
                                                            attribute_category,
                                                            attribute1,
                                                            attribute5,
                                                            attribute12,
                                                            PRIMARY_VENDOR_ITEM)
                          VALUES (v_asl_id,
                                  -1,
                                  c.organization_id,
                                  c.vendor_business_type,
                                  c.asl_status_id,
                                  SYSDATE,
                                  g_user_id,
                                  SYSDATE,
                                  g_user_id,
                                  c.vendor_id,
                                  v_item_id,
                                  c.vendor_site_id,
                                  c.shelf_life,
                                  c.product_spec_num,
                                  c.product_spec_version,
                                  fnd_date.date_to_canonical (c.product_spec_valid_to),
                                  c.country,
                                  TO_CHAR (c.packing_size),
                                  TO_CHAR (c.pallet_size),
                                  c.need_forestry_cert,
                                  c.forestry_cert_body,
                                  fnd_date.date_to_canonical (c.forestry_cert_valid_to),
                                  c.forestry_cert_num,
                                  c.supplier_item);

                     INSERT INTO po_asl_attributes (asl_id,
                                                    using_organization_id,
                                                    document_sourcing_method,
                                                    last_update_date,
                                                    last_updated_by,
                                                    creation_date,
                                                    created_by,
                                                    vendor_id,
                                                    item_id,
                                                    vendor_site_id,
                                                    enable_plan_schedule_flag,
                                                    enable_ship_schedule_flag,
                                                    enable_autoschedule_flag,
                                                    enable_authorizations_flag,
                                                    last_update_login,
                                                    enable_vmi_flag,
                                                    processing_lead_time,
                                                    min_order_qty,
                                                    fixed_lot_multiple,
                                                    RELEASE_GENERATION_METHOD)
                          VALUES (v_asl_id,
                                  -1,
                                  'ASL',
                                  SYSDATE,
                                  g_user_id,
                                  SYSDATE,
                                  g_user_id,
                                  c.vendor_id,
                                  v_item_id,
                                  c.vendor_site_id,
                                  'N',
                                  'N',
                                  'N',
                                  'N',
                                  g_login_id,
                                  'N',
                                  c.processing_lead_time,
                                  c.min_order_qty,
                                  c.fixed_lot_multiple,
                                  c.RELEASE_METHOD);

                     IF SQL%ROWCOUNT > 0
                     THEN
                        UPDATE xxshp_po_asl_attributes
                           SET status = 'S',
                               po_asl_id = v_asl_id,
                               last_update_date = SYSDATE,
                               last_updated_by = g_user_id,
                               last_update_login = g_login_id
                         WHERE ROWID = c.rid;

                        v_success := v_success + 1;
                     END IF;
                  END IF;
               END LOOP;

               UPDATE xxshp_inv_master_item_reg
                  SET status_iface_asl = 'P' /*Processed
                                             */
                                            ,
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE reg_hdr_id = p_reg_hdr_id;
            ELSE
               UPDATE xxshp_inv_master_item_reg
                  SET status_iface_asl = 'E',
                      message_iface_asl = 'Item is not found.',
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE reg_hdr_id = p_reg_hdr_id;
            END IF;

            logf ('Item :' || v_item_code);
            logf ('--> Success : ' || TO_CHAR (v_success));
            logf ('--> Fail : ' || TO_CHAR (v_failed));
         ELSE
            /* Pecah KN
            */
            FOR ckn IN (SELECT *
                          FROM xxshp_inv_master_item_kn kn
                         WHERE kn.reg_hdr_id = p_reg_hdr_id AND kn.item_id IS NOT NULL)
            LOOP
               FOR c IN cur_asl
               LOOP
                  x_record_unique :=
                     po_asl_sv.check_record_unique (NULL,
                                                    c.vendor_id,
                                                    c.vendor_site_id,
                                                    ckn.item_id,
                                                    NULL,
                                                    -1);

                  IF NOT x_record_unique
                  THEN
                     UPDATE xxshp_po_asl_attributes
                        SET MESSAGE =
                                  MESSAGE
                               || 'Duplicate Supplier/Supplier Site being defined for Item/Commodity for item '
                               || ckn.item_code
                               || CHR (10),
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE ROWID = c.rid;

                     v_failed := v_failed + 1;
                  ELSE
                     SELECT po_approved_supplier_list_s.NEXTVAL INTO v_asl_id FROM DUAL;

                     logf ('Inserting asl_id: ' || v_asl_id);

                     INSERT INTO po_approved_supplier_list (asl_id,
                                                            using_organization_id,
                                                            owning_organization_id,
                                                            vendor_business_type,
                                                            asl_status_id,
                                                            last_update_date,
                                                            last_updated_by,
                                                            creation_date,
                                                            created_by,
                                                            vendor_id,
                                                            item_id,
                                                            vendor_site_id,
                                                            attribute2,
                                                            attribute6,
                                                            attribute8,
                                                            attribute9,
                                                            attribute10,
                                                            attribute11,
                                                            attribute13,
                                                            attribute_category,
                                                            attribute1,
                                                            attribute5,
                                                            attribute12,
                                                            PRIMARY_VENDOR_ITEM)
                          VALUES (v_asl_id,
                                  -1,
                                  c.organization_id,
                                  c.vendor_business_type,
                                  c.asl_status_id,
                                  SYSDATE,
                                  g_user_id,
                                  SYSDATE,
                                  g_user_id,
                                  c.vendor_id,
                                  ckn.item_id,
                                  c.vendor_site_id,
                                  c.shelf_life,
                                  c.product_spec_num,
                                  c.product_spec_version,
                                  fnd_date.date_to_canonical (c.product_spec_valid_to),
                                  c.country,
                                  TO_CHAR (c.packing_size),
                                  TO_CHAR (c.pallet_size),
                                  c.need_forestry_cert,
                                  c.forestry_cert_body,
                                  fnd_date.date_to_canonical (c.forestry_cert_valid_to),
                                  c.forestry_cert_num,
                                  c.supplier_item);

                     INSERT INTO po_asl_attributes (asl_id,
                                                    using_organization_id,
                                                    document_sourcing_method,
                                                    last_update_date,
                                                    last_updated_by,
                                                    creation_date,
                                                    created_by,
                                                    vendor_id,
                                                    item_id,
                                                    vendor_site_id,
                                                    enable_plan_schedule_flag,
                                                    enable_ship_schedule_flag,
                                                    enable_autoschedule_flag,
                                                    enable_authorizations_flag,
                                                    last_update_login,
                                                    enable_vmi_flag,
                                                    processing_lead_time,
                                                    min_order_qty,
                                                    fixed_lot_multiple,
                                                    RELEASE_GENERATION_METHOD)
                          VALUES (v_asl_id,
                                  -1,
                                  'ASL',
                                  SYSDATE,
                                  g_user_id,
                                  SYSDATE,
                                  g_user_id,
                                  c.vendor_id,
                                  ckn.item_id,
                                  c.vendor_site_id,
                                  'N',
                                  'N',
                                  'N',
                                  'N',
                                  g_login_id,
                                  'N',
                                  c.processing_lead_time,
                                  c.min_order_qty,
                                  c.fixed_lot_multiple,
                                  c.RELEASE_METHOD);

                     IF SQL%ROWCOUNT > 0
                     THEN
                        UPDATE xxshp_po_asl_attributes
                           SET MESSAGE =
                                     MESSAGE
                                  || 'Status Item '
                                  || ckn.item_code
                                  || ' : S and PO_ASL_ID : '
                                  || v_asl_id
                                  || CHR (10),
                               last_update_date = SYSDATE,
                               last_updated_by = g_user_id,
                               last_update_login = g_login_id
                         WHERE ROWID = c.rid;

                        v_success := v_success + 1;
                     END IF;
                  END IF;
               END LOOP;

               UPDATE xxshp_inv_master_item_kn
                  SET status_iface_asl = 'P' /* Processed
                                             */
                                            ,
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE kn_id = ckn.kn_id;

               logf ('Item KN: ' || ckn.item_code);
               logf ('--> Success :' || TO_CHAR (v_success));
               logf ('--> Fail :' || TO_CHAR (v_failed));
            END LOOP;
         END IF;

         --END IF;

         COMMIT;
      END IF;
   EXCEPTION
      WHEN OTHERS
      THEN
         logf ('Error on creata_asl_attributes: ' || SQLERRM);
   END create_asl_attributes;

   PROCEDURE create_mfg_part_numbers (p_reg_hdr_id IN NUMBER)
   /*
        Created by EY on 15-Mar-2017

        History Update:
   */
   IS
      v_count           NUMBER;
      v_mfg_id          NUMBER;
      v_master_io       NUMBER;
      v_item_id         NUMBER;
      v_split_kn_flag   VARCHAR2 (1);
      v_item_code       mtl_system_items_kfv.concatenated_segments%TYPE;
      v_supply_type     xxshp_inv_master_item_reg.supply_type%TYPE;
      v_validate        NUMBER;

      CURSOR cur_mfg
      IS
         SELECT xim.ROWID mfg_rid, xim.*
           FROM xxshp_inv_manufacturers xim
          WHERE xim.reg_hdr_id = p_reg_hdr_id;

      CURSOR cur_mfg_part (p_mfg_id IN NUMBER)
      IS
         SELECT ximpn.ROWID mfg_part_rid, ximpn.*
           FROM xxshp_inv_mfg_part_numbers ximpn
          WHERE ximpn.mfg_id = p_mfg_id;
   BEGIN
      SELECT COUNT (1)
        INTO v_validate
        FROM (SELECT *
                FROM xxshp_inv_master_item_reg
               WHERE     SPLIT_KN_FLAG = 'N'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND NVL (status_iface_manufactur, 'E') = 'E'
              UNION ALL
              SELECT *
                FROM xxshp_inv_master_item_reg reg
               WHERE     SPLIT_KN_FLAG = 'Y'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND EXISTS
                            (SELECT 1
                               FROM xxshp_inv_master_item_kn kn
                              WHERE     NVL (status_iface_manufactur, 'E') = 'E'
                                    AND kn.reg_hdr_id = reg.reg_hdr_id));


      IF (v_validate = 0)
      THEN
         logf ('No row to process');
      ELSE
         SELECT NVL (split_kn_flag, 'N'),
                item_id,
                item_code,
                supply_type,
                master_organization_id
           INTO v_split_kn_flag,
                v_item_id,
                v_item_code,
                v_supply_type,
                v_master_io
           FROM xxshp_inv_master_item_reg ximir, mtl_parameters mp
          WHERE ximir.organization_id = mp.organization_id AND ximir.reg_hdr_id = p_reg_hdr_id;

         --IF v_supply_type IN ('BUY', 'MAKE')
         --THEN
         IF v_split_kn_flag = 'N'
         THEN
            IF v_item_id IS NOT NULL
            THEN
               FOR c IN cur_mfg
               LOOP
                  BEGIN
                     SELECT COUNT (1)
                       INTO v_count
                       FROM mtl_manufacturers mm
                      WHERE mm.manufacturer_name = c.manufacturer_name;
                  EXCEPTION
                     WHEN NO_DATA_FOUND
                     THEN
                        v_count := 0;
                  END;

                  IF v_count > 0
                  THEN
                     logf ('Manufacturer : ' || c.manufacturer_name || ' already exists');

                     UPDATE xxshp_inv_manufacturers
                        SET status = 'E',
                            MESSAGE = 'Manufacturer : ' || c.manufacturer_name || ' already exists',
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE ROWID = c.mfg_rid;

                     BEGIN
                        SELECT manufacturer_id
                          INTO v_mfg_id
                          FROM mtl_manufacturers mm
                         WHERE mm.manufacturer_name = c.manufacturer_name;
                     EXCEPTION
                        WHEN OTHERS
                        THEN
                           logf ('Failed when get manufacturer_id ' || SQLERRM);
                     END;
                  ELSE
                     SELECT mtl_manufacturers_s.NEXTVAL INTO v_mfg_id FROM DUAL;

                     logf ('Inserting manufacturer_id: ' || v_mfg_id);

                     INSERT INTO mtl_manufacturers (manufacturer_id,
                                                    manufacturer_name,
                                                    last_update_date,
                                                    last_updated_by,
                                                    creation_date,
                                                    created_by,
                                                    description,
                                                    attribute2,
                                                    attribute3,
                                                    attribute8,
                                                    attribute1,
                                                    attribute12,
                                                    attribute13)
                          VALUES (v_mfg_id,
                                  c.manufacturer_name,
                                  SYSDATE,
                                  g_user_id,
                                  SYSDATE,
                                  g_user_id,
                                  c.description,
                                  c.country,
                                  c.factory_code,
                                  c.comments,
                                  c.mfg_status,
                                  TO_CHAR (c.vendor_id),
                                  TO_CHAR (c.vendor_site_id));



                     UPDATE xxshp_inv_manufacturers
                        SET status = 'S',
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE ROWID = c.mfg_rid;
                  END IF;


                  IF (v_mfg_id IS NOT NULL)
                  THEN
                     FOR cp IN cur_mfg_part (c.mfg_id)
                     LOOP
                        SELECT COUNT (1)
                          INTO v_count
                          FROM mtl_mfg_part_numbers
                         WHERE     organization_id = v_master_io
                               AND manufacturer_id = v_mfg_id
                               AND inventory_item_id = v_item_id
                               AND mfg_part_num = cp.mfg_part_num;


                        IF (v_count > 0)
                        THEN
                           logf (
                              'Manufacturer part number : ' || cp.mfg_part_num || ' already exists');

                           UPDATE xxshp_inv_mfg_part_numbers
                              SET status = 'E',
                                  MESSAGE =
                                     SUBSTR (
                                           MESSAGE
                                        || 'Duplicate Manufacturer Part Number '
                                        || CHR (10),
                                        1,
                                        2000)
                            WHERE ROWID = cp.mfg_part_rid;
                        ELSE
                           INSERT INTO mtl_mfg_part_numbers (manufacturer_id,
                                                             mfg_part_num,
                                                             inventory_item_id,
                                                             last_update_date,
                                                             last_updated_by,
                                                             creation_date,
                                                             created_by,
                                                             organization_id,
                                                             attribute3,
                                                             attribute2,
                                                             attribute4,
                                                             attribute5,
                                                             attribute6,
                                                             attribute7,
                                                             attribute8,
                                                             attribute13,
                                                             attribute14,
                                                             attribute15,
                                                             attribute_category,
                                                             attribute9,
                                                             attribute10,
                                                             attribute11,
                                                             attribute12)
                                   VALUES (
                                             v_mfg_id,
                                             cp.mfg_part_num,
                                             v_item_id,
                                             SYSDATE,
                                             g_user_id,
                                             SYSDATE,
                                             g_user_id,
                                             v_master_io,
                                             cp.allergen_num,
                                             fnd_date.date_to_canonical (cp.allergen_valid_to),
                                             cp.certificate_md_num,
                                             fnd_date.date_to_canonical (
                                                cp.certificate_md_valid_to),
                                             cp.akasia_num,
                                             cp.prod_qm_version,
                                             fnd_date.date_to_canonical (cp.prod_qm_valid_to),
                                             cp.organic_certificate_num,
                                             fnd_date.date_to_canonical (
                                                cp.organic_certificate_valid_to),
                                             cp.organic_body,
                                             cp.need_halal_certificate,
                                             cp.halal_certificate_num,
                                             fnd_date.date_to_canonical (
                                                cp.halal_certificate_valid_to),
                                             cp.halal_logo,
                                             cp.halal_body);

                           UPDATE xxshp_inv_mfg_part_numbers
                              SET status = 'S',
                                  last_update_date = SYSDATE,
                                  last_updated_by = g_user_id,
                                  last_update_login = g_login_id
                            WHERE ROWID = cp.mfg_part_rid;
                        END IF;
                     END LOOP;
                  END IF;
               END LOOP;

               UPDATE xxshp_inv_master_item_reg
                  SET status_iface_manufactur = 'P',
                      status_iface_part_num = 'P' /*Processed
                                                  */
                                                 ,
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE reg_hdr_id = p_reg_hdr_id;
            ELSE
               UPDATE xxshp_inv_master_item_reg
                  SET status_iface_manufactur = 'E',
                      message_iface_manufactur = 'Item is not found.',
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE reg_hdr_id = p_reg_hdr_id;
            END IF;
         ELSE
            /* Pecah KN */
            FOR c IN cur_mfg
            LOOP
               BEGIN
                  SELECT COUNT (1)
                    INTO v_count
                    FROM mtl_manufacturers mm
                   WHERE mm.manufacturer_name = c.manufacturer_name;
               EXCEPTION
                  WHEN NO_DATA_FOUND
                  THEN
                     v_count := 0;
               END;

               IF v_count > 0
               THEN
                  logf ('Manufacturer : ' || c.manufacturer_name || ' already exists');

                  UPDATE xxshp_inv_manufacturers
                     SET status = 'E',
                         MESSAGE =
                               'Manufacturer : '
                            || c.manufacturer_name
                            || ' already exists '
                            || CHR (10),
                         last_update_date = SYSDATE,
                         last_updated_by = g_user_id,
                         last_update_login = g_login_id
                   WHERE ROWID = c.mfg_rid;

                  BEGIN
                     SELECT manufacturer_id
                       INTO v_mfg_id
                       FROM mtl_manufacturers mm
                      WHERE mm.manufacturer_name = c.manufacturer_name;
                  EXCEPTION
                     WHEN OTHERS
                     THEN
                        logf ('Failed when get manufacturer_id ' || SQLERRM);
                  END;
               ELSE
                  SELECT mtl_manufacturers_s.NEXTVAL INTO v_mfg_id FROM DUAL;

                  logf ('Inserting manufacturer_id: ' || v_mfg_id);

                  INSERT INTO mtl_manufacturers (manufacturer_id,
                                                 manufacturer_name,
                                                 last_update_date,
                                                 last_updated_by,
                                                 creation_date,
                                                 created_by,
                                                 description,
                                                 attribute2,
                                                 attribute3,
                                                 attribute8,
                                                 attribute1,
                                                 attribute12,
                                                 attribute13)
                       VALUES (v_mfg_id,
                               c.manufacturer_name,
                               SYSDATE,
                               g_user_id,
                               SYSDATE,
                               g_user_id,
                               c.description,
                               c.country,
                               c.factory_code,
                               c.comments,
                               c.mfg_status,
                               TO_CHAR (c.vendor_id),
                               TO_CHAR (c.vendor_site_id));
               END IF;

               IF (v_mfg_id IS NOT NULL)
               THEN
                  FOR cp IN cur_mfg_part (c.mfg_id)
                  LOOP
                     FOR ckn IN (SELECT *
                                   FROM xxshp_inv_master_item_kn kn
                                  WHERE kn.reg_hdr_id = p_reg_hdr_id AND kn.item_id IS NOT NULL)
                     LOOP
                        SELECT COUNT (1)
                          INTO v_count
                          FROM mtl_mfg_part_numbers
                         WHERE     organization_id = v_master_io
                               AND manufacturer_id = v_mfg_id
                               AND inventory_item_id = ckn.item_id
                               AND mfg_part_num = cp.mfg_part_num;

                        IF v_count > 0
                        THEN
                           logf (
                              'Manufacturer part number : ' || cp.mfg_part_num || ' already exists');

                           UPDATE xxshp_inv_mfg_part_numbers
                              SET status = 'E',
                                  MESSAGE =
                                     SUBSTR (
                                           MESSAGE
                                        || 'Duplicate Manufacturer Part Number for item '
                                        || ckn.item_code
                                        || CHR (10),
                                        1,
                                        2000)
                            WHERE ROWID = cp.mfg_part_rid;
                        ELSE
                           INSERT INTO mtl_mfg_part_numbers (manufacturer_id,
                                                             mfg_part_num,
                                                             inventory_item_id,
                                                             last_update_date,
                                                             last_updated_by,
                                                             creation_date,
                                                             created_by,
                                                             organization_id,
                                                             attribute3,
                                                             attribute2,
                                                             attribute4,
                                                             attribute5,
                                                             attribute6,
                                                             attribute7,
                                                             attribute8,
                                                             attribute13,
                                                             attribute14,
                                                             attribute15,
                                                             attribute_category,
                                                             attribute9,
                                                             attribute10,
                                                             attribute11,
                                                             attribute12)
                                VALUES (v_mfg_id,
                                        cp.mfg_part_num,
                                        ckn.item_id,
                                        SYSDATE,
                                        g_user_id,
                                        SYSDATE,
                                        g_user_id,
                                        v_master_io,
                                        cp.allergen_num,
                                        cp.allergen_valid_to,
                                        cp.certificate_md_num,
                                        cp.certificate_md_valid_to,
                                        cp.akasia_num,
                                        cp.prod_qm_version,
                                        cp.prod_qm_valid_to,
                                        cp.organic_certificate_num,
                                        cp.organic_certificate_valid_to,
                                        cp.organic_body,
                                        cp.need_halal_certificate,
                                        cp.halal_certificate_num,
                                        cp.halal_certificate_valid_to,
                                        cp.halal_logo,
                                        cp.halal_body);

                           UPDATE xxshp_inv_mfg_part_numbers
                              SET MESSAGE =
                                     SUBSTR (
                                           MESSAGE
                                        || 'Status Item '
                                        || ckn.item_code
                                        || ' : S for Part Number '
                                        || cp.mfg_part_num
                                        || CHR (10),
                                        1,
                                        2000),
                                  last_update_date = SYSDATE,
                                  last_updated_by = g_user_id,
                                  last_update_login = g_login_id
                            WHERE ROWID = cp.mfg_part_rid;
                        END IF;


                        UPDATE xxshp_inv_master_item_kn
                           SET status_iface_manufactur = 'P',
                               status_iface_part_num = 'P' /* Processed
                                                           */
                                                          ,
                               last_update_date = SYSDATE,
                               last_updated_by = g_user_id,
                               last_update_login = g_login_id
                         WHERE kn_id = ckn.kn_id;

                        UPDATE xxshp_inv_manufacturers
                           SET MESSAGE =
                                  SUBSTR (
                                        MESSAGE
                                     || 'Status Item '
                                     || ckn.item_code
                                     || ' : S for Manufacturer '
                                     || c.manufacturer_name
                                     || CHR (10),
                                     1,
                                     2000),
                               last_update_date = SYSDATE,
                               last_updated_by = g_user_id,
                               last_update_login = g_login_id
                         WHERE ROWID = c.mfg_rid;
                     END LOOP;
                  END LOOP;
               END IF;
            END LOOP;
         END IF;

         --END IF;

         COMMIT;
      END IF;
   EXCEPTION
      WHEN OTHERS
      THEN
         logf ('Error on create_mfg_part_numbers: ' || SQLERRM);
   END create_mfg_part_numbers;

   PROCEDURE create_bill_of_dist (p_reg_hdr_id IN NUMBER)
   /*
        Created by EY on 16-Mar-2017

        History Update:
   */
   IS
      v_sr_seq        NUMBER;
      v_rcpt_seq      NUMBER;
      v_src_seq       NUMBER;
      v_instance_id   NUMBER;
      v_err_msg       VARCHAR2 (2000);
      v_count         NUMBER := 0;
      v_validate      NUMBER;

      CURSOR cur_sr
      IS
         SELECT *
           FROM xxshp_msc_sourcing_rules xmsr
          WHERE xmsr.reg_hdr_id = p_reg_hdr_id AND sourcing_rule_id IS NULL;

      CURSOR cur_rcpt (p_sr_id IN NUMBER)
      IS
         SELECT *
           FROM xxshp_msc_sr_receipt_org xmsro
          WHERE xmsro.sr_id = p_sr_id AND xmsro.sr_receipt_id IS NULL;

      CURSOR cur_src (p_sr_rcpt_id IN NUMBER)
      IS
         SELECT *
           FROM xxshp_msc_sr_source_org xmsso
          WHERE xmsso.sr_rcpt_id = p_sr_rcpt_id AND xmsso.sr_source_id IS NULL;
   BEGIN
      SELECT COUNT (1)
        INTO v_validate
        FROM (SELECT *
                FROM xxshp_inv_master_item_reg
               WHERE     SPLIT_KN_FLAG = 'N'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND NVL (status_iface_bod, 'E') = 'E'
              UNION ALL
              SELECT *
                FROM xxshp_inv_master_item_reg reg
               WHERE     SPLIT_KN_FLAG = 'Y'
                     AND NVL (status_iface_bod, 'E') = 'E'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND EXISTS
                            (SELECT 1
                               FROM xxshp_inv_master_item_kn kn
                              WHERE kn.reg_hdr_id = reg.reg_hdr_id));


      IF (v_validate = 0)
      THEN
         logf ('No row to process');
      ELSE
         SELECT instance_id
           INTO v_instance_id
           FROM msc_apps_instances@apps_to_apps
          WHERE instance_code = 'KNS' AND enable_flag = 1 AND ROWNUM <= 1;

         FOR c IN cur_sr
         LOOP
            BEGIN
               SELECT msc_sourcing_rules_s.NEXTVAL@apps_to_apps INTO v_sr_seq FROM DUAL;

               /**
               sourcing_rule_type = 2 = bill of distribution
               */
               INSERT INTO msc_sourcing_rules@apps_to_apps (sourcing_rule_id,
                                                            sr_sourcing_rule_id,
                                                            sr_instance_id,
                                                            sourcing_rule_name,
                                                            description,
                                                            status,
                                                            sourcing_rule_type,
                                                            planning_active,
                                                            last_update_date,
                                                            last_updated_by,
                                                            creation_date,
                                                            created_by)
                    VALUES (v_sr_seq,
                            -1 * v_sr_seq,
                            v_instance_id,
                            c.sourcing_rule_name,
                            c.description,
                            1,
                            2,
                            1,
                            SYSDATE,
                            g_user_id,
                            SYSDATE,
                            g_user_id);

               FOR cr IN cur_rcpt (c.sr_id)
               LOOP
                  BEGIN
                     SELECT msc_sr_receipt_org_s.NEXTVAL@apps_to_apps INTO v_rcpt_seq FROM DUAL;

                     INSERT INTO msc.msc_sr_receipt_org@apps_to_apps (sr_receipt_id,
                                                                      sr_instance_id,
                                                                      sr_receipt_org,
                                                                      receipt_org_instance_id,
                                                                      sr_sr_receipt_id,
                                                                      sourcing_rule_id,
                                                                      effective_date,
                                                                      disable_date,
                                                                      last_update_date,
                                                                      last_updated_by,
                                                                      creation_date,
                                                                      created_by)
                          VALUES (v_rcpt_seq,
                                  v_instance_id,
                                  cr.sr_receipt_org,
                                  cr.receipt_org_instance_id,
                                  -1 * v_rcpt_seq,
                                  v_sr_seq,
                                  cr.effective_date,
                                  cr.disable_date,
                                  SYSDATE,
                                  g_user_id,
                                  SYSDATE,
                                  g_user_id);

                     FOR cs IN cur_src (cr.sr_rcpt_id)
                     LOOP
                        BEGIN
                           SELECT msc_sr_source_org_s.NEXTVAL@apps_to_apps INTO v_src_seq FROM DUAL;

                           INSERT INTO msc.msc_sr_source_org@apps_to_apps (sr_source_id,
                                                                           sr_sr_source_id,
                                                                           sr_receipt_id,
                                                                           source_partner_id,
                                                                           source_partner_site_id,
                                                                           allocation_percent,
                                                                           RANK,
                                                                           source_type,
                                                                           sr_instance_id,
                                                                           source_organization_id,
                                                                           source_org_instance_id,
                                                                           last_update_date,
                                                                           last_updated_by,
                                                                           creation_date,
                                                                           created_by)
                                VALUES (v_src_seq,
                                        -1 * v_src_seq,
                                        v_rcpt_seq,
                                        cs.source_partner_id,
                                        cs.source_partner_site_id,
                                        cs.allocation_percent,
                                        cs.RANK,
                                        cs.source_type,
                                        v_instance_id,
                                        cs.source_organization_id,
                                        cs.source_org_instance_id,
                                        SYSDATE,
                                        g_user_id,
                                        SYSDATE,
                                        g_user_id);

                           UPDATE xxshp_msc_sr_source_org
                              SET sr_source_id = v_src_seq,
                                  status = 'S',
                                  last_update_date = SYSDATE,
                                  last_updated_by = g_user_id,
                                  last_update_login = g_login_id
                            WHERE sr_src_id = cs.sr_src_id;
                        EXCEPTION
                           WHEN OTHERS
                           THEN
                              v_err_msg := SUBSTR (SQLERRM, 1, 2000);

                              UPDATE xxshp_msc_sr_source_org
                                 SET status = 'E',
                                     MESSAGE = v_err_msg,
                                     last_update_date = SYSDATE,
                                     last_updated_by = g_user_id,
                                     last_update_login = g_login_id
                               WHERE sr_src_id = cs.sr_src_id;
                        END;
                     END LOOP;

                     UPDATE xxshp_msc_sr_receipt_org
                        SET sr_receipt_id = v_rcpt_seq,
                            status = 'S',
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE sr_rcpt_id = cr.sr_rcpt_id;
                  EXCEPTION
                     WHEN OTHERS
                     THEN
                        v_err_msg := SUBSTR (SQLERRM, 1, 2000);

                        UPDATE xxshp_msc_sr_receipt_org
                           SET status = 'E',
                               MESSAGE = v_err_msg,
                               last_update_date = SYSDATE,
                               last_updated_by = g_user_id,
                               last_update_login = g_login_id
                         WHERE sr_rcpt_id = cr.sr_rcpt_id;
                  END;
               END LOOP;

               UPDATE xxshp_msc_sourcing_rules
                  SET sourcing_rule_id = v_sr_seq,
                      status = 'S',
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE sr_id = c.sr_id;
            EXCEPTION
               WHEN OTHERS
               THEN
                  v_err_msg := SUBSTR (SQLERRM, 1, 2000);

                  UPDATE xxshp_msc_sourcing_rules
                     SET status = 'E',
                         MESSAGE = v_err_msg,
                         last_update_date = SYSDATE,
                         last_updated_by = g_user_id,
                         last_update_login = g_login_id
                   WHERE sr_id = c.sr_id;
            END;

            v_count := 1;
         END LOOP;

         IF v_count > 0
         THEN
            UPDATE xxshp_inv_master_item_reg
               SET status_iface_bod = 'P' /* Processed
                                              */
                                         ,
                   last_update_date = SYSDATE,
                   last_updated_by = g_user_id,
                   last_update_login = g_login_id
             WHERE reg_hdr_id = p_reg_hdr_id;
         END IF;

         COMMIT;
      END IF;
   EXCEPTION
      WHEN OTHERS
      THEN
         logf ('Error on create_bill_of_dist: ' || SQLERRM);
   END create_bill_of_dist;

   PROCEDURE assign_item_category (p_reg_hdr_id IN NUMBER, x_return OUT NUMBER)
   /*
        Created by EY on 17-Mar-2017

        History Update:
   */
   IS
      v_val                NUMBER;
      v_err                NUMBER := 0;
      v_err_msg            VARCHAR2 (2000);
      v_message            VARCHAR2 (2000);
      v_status             VARCHAR2 (100);
      v_request_id         NUMBER;
      v_mst_item_reg       xxshp_inv_master_item_reg%ROWTYPE;
      v_set_process_id     NUMBER;
      v_validate           NUMBER;
      v_transaction_type   VARCHAR2 (20);
      v_old_category_id    NUMBER;
      v_default_category   NUMBER;
   BEGIN
      fnd_global.apps_initialize (g_user_id, g_resp_id, g_resp_appl_id);

      SELECT COUNT (1)
        INTO v_validate
        FROM (SELECT *
                FROM xxshp_inv_master_item_reg
               WHERE     SPLIT_KN_FLAG = 'N'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND NVL (status_iface_item_cat, 'E') = 'E'
              UNION ALL
              SELECT *
                FROM xxshp_inv_master_item_reg reg
               WHERE     SPLIT_KN_FLAG = 'Y'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND NVL (status_iface_item_cat, 'E') = 'E'
                     AND EXISTS
                            (SELECT 1
                               FROM xxshp_inv_master_item_kn kn
                              WHERE kn.reg_hdr_id = reg.reg_hdr_id));


      IF (v_validate = 0)
      THEN
         logf ('No row to process');
      ELSE
         SELECT *
           INTO v_mst_item_reg
           FROM xxshp_inv_master_item_reg
          WHERE reg_hdr_id = p_reg_hdr_id;

         v_set_process_id := v_mst_item_reg.set_process_id;

         ----delete previous error transaction
         DELETE mtl_item_categories_interface
          WHERE set_process_id = v_set_process_id;

         SELECT COUNT (1)
           INTO v_val
           FROM mtl_item_categories_interface
          WHERE set_process_id = v_mst_item_reg.set_process_id;

         IF (v_val = 0)
         THEN
            mo_global.init ('INV');

            FOR c IN (SELECT ximic.*
                        FROM xxshp_inv_master_item_cat_v ximic
                       WHERE ximic.reg_hdr_id = p_reg_hdr_id)
            LOOP
               IF c.item_type = g_item_type_parent
               THEN
                  IF v_mst_item_reg.item_id IS NOT NULL
                  THEN
                     BEGIN
                        SELECT COUNT (1)
                          INTO v_default_category
                          FROM MTL_DEFAULT_CATEGORY_SETS_FK_V
                         WHERE category_set_id = c.category_set_id;

                        IF (v_default_category > 0)
                        THEN
                           v_transaction_type := 'UPDATE';

                           SELECT default_category_id
                             INTO v_old_category_id
                             FROM mtl_category_sets
                            WHERE category_set_id = c.category_set_id;
                        ELSE
                           v_transaction_type := 'CREATE';
                           v_old_category_id := NULL;
                        END IF;

                        INSERT INTO mtl_item_categories_interface (item_number,
                                                                   category_set_id,
                                                                   category_id,
                                                                   old_category_id,
                                                                   organization_id,
                                                                   transaction_type,
                                                                   process_flag,
                                                                   set_process_id)
                             VALUES (v_mst_item_reg.item_code,
                                     c.category_set_id,
                                     c.category_id,
                                     v_old_category_id,
                                     v_mst_item_reg.organization_id,
                                     v_transaction_type,
                                     1,
                                     v_set_process_id);
                     EXCEPTION
                        WHEN OTHERS
                        THEN
                           v_err_msg :=
                                 'Item '
                              || v_mst_item_reg.item_code
                              || ': '
                              || SUBSTR (SQLERRM, 1, 2000)
                              || CHR (10);

                           UPDATE xxshp_inv_master_item_cat
                              SET status = 'E',
                                  MESSAGE = v_err_msg,
                                  last_update_date = SYSDATE,
                                  last_updated_by = g_user_id,
                                  last_update_login = g_login_id
                            WHERE cat_id = c.cat_id;

                           v_err := 1;
                     END;
                  END IF;
               ELSIF c.item_type LIKE g_item_type_kn || '%'
               THEN
                  FOR ckn
                     IN (SELECT *
                           FROM xxshp_inv_master_item_kn ximik
                          WHERE     ximik.reg_hdr_id = p_reg_hdr_id
                                AND item_code LIKE '%' || c.item_type
                                AND item_id IS NOT NULL)
                  LOOP
                     BEGIN
                        SELECT COUNT (1)
                          INTO v_default_category
                          FROM MTL_DEFAULT_CATEGORY_SETS_FK_V
                         WHERE category_set_id = c.category_set_id;

                        IF (v_default_category > 0)
                        THEN
                           v_transaction_type := 'UPDATE';

                           SELECT default_category_id
                             INTO v_old_category_id
                             FROM mtl_category_sets
                            WHERE category_set_id = c.category_set_id;
                        ELSE
                           v_transaction_type := 'CREATE';
                           v_old_category_id := NULL;
                        END IF;

                        INSERT INTO mtl_item_categories_interface (item_number,
                                                                   category_set_id,
                                                                   category_id,
                                                                   old_category_id,
                                                                   organization_id,
                                                                   transaction_type,
                                                                   process_flag,
                                                                   set_process_id)
                             VALUES (ckn.item_code,
                                     c.category_set_id,
                                     c.category_id,
                                     v_old_category_id,
                                     v_mst_item_reg.organization_id,
                                     v_transaction_type,
                                     1,
                                     v_set_process_id);
                     EXCEPTION
                        WHEN OTHERS
                        THEN
                           v_err_msg :=
                                 'Item '
                              || ckn.item_code
                              || ': '
                              || SUBSTR (SQLERRM, 1, 2000)
                              || CHR (10);

                           UPDATE xxshp_inv_master_item_cat
                              SET status = 'E',
                                  MESSAGE = SUBSTR (MESSAGE || '#' || v_err_msg, 1, 2000),
                                  last_update_date = SYSDATE,
                                  last_updated_by = g_user_id,
                                  last_update_login = g_login_id
                            WHERE cat_id = c.cat_id;

                           v_err := 1;
                     END;
                  END LOOP;
               ELSIF c.item_type LIKE g_item_type_unstd || '%'
               THEN
                  FOR cunstd
                     IN (SELECT *
                           FROM xxshp_inv_master_item_unstd ximiu
                          WHERE     ximiu.reg_hdr_id = p_reg_hdr_id
                                AND item_code LIKE c.item_type || '%'
                                AND ximiu.item_id IS NOT NULL)
                  LOOP
                     BEGIN
                        SELECT COUNT (1)
                          INTO v_default_category
                          FROM MTL_DEFAULT_CATEGORY_SETS_FK_V
                         WHERE category_set_id = c.category_set_id;

                        IF (v_default_category > 0)
                        THEN
                           v_transaction_type := 'UPDATE';

                           SELECT default_category_id
                             INTO v_old_category_id
                             FROM mtl_category_sets
                            WHERE category_set_id = c.category_set_id;
                        ELSE
                           v_transaction_type := 'CREATE';
                           v_old_category_id := NULL;
                        END IF;

                        INSERT INTO mtl_item_categories_interface (item_number,
                                                                   category_set_id,
                                                                   category_id,
                                                                   old_category_id,
                                                                   organization_id,
                                                                   transaction_type,
                                                                   process_flag,
                                                                   set_process_id)
                             VALUES (cunstd.item_code,
                                     c.category_set_id,
                                     c.category_id,
                                     v_old_category_id,
                                     v_mst_item_reg.organization_id,
                                     v_transaction_type,
                                     1,
                                     v_set_process_id);
                     EXCEPTION
                        WHEN OTHERS
                        THEN
                           v_err_msg :=
                                 'Item '
                              || cunstd.item_code
                              || ': '
                              || SUBSTR (SQLERRM, 1, 2000)
                              || CHR (10);

                           UPDATE xxshp_inv_master_item_cat
                              SET status = 'E',
                                  MESSAGE = SUBSTR (MESSAGE || '#' || v_err_msg, 1, 2000),
                                  last_update_date = SYSDATE,
                                  last_updated_by = g_user_id,
                                  last_update_login = g_login_id
                            WHERE cat_id = c.cat_id;

                           v_err := 1;
                     END;
                  END LOOP;
               ELSIF c.item_type LIKE g_item_type_tollfee || '%'
               THEN
                  FOR ctf
                     IN (SELECT *
                           FROM xxshp_inv_master_item_toll ximit
                          WHERE     ximit.reg_hdr_id = p_reg_hdr_id
                                AND SUBSTR (c.item_type, 2) =
                                       reverse (
                                          SUBSTR (
                                             reverse (item_description),
                                             (INSTR (reverse (item_description), ' ') + 1),
                                             (  INSTR (reverse (item_description),
                                                       ' ',
                                                       1,
                                                       2)
                                              - (INSTR (reverse (item_description), ' ') + 1))))
                                AND ximit.item_id IS NOT NULL)
                  LOOP
                     BEGIN
                        SELECT COUNT (1)
                          INTO v_default_category
                          FROM MTL_DEFAULT_CATEGORY_SETS_FK_V
                         WHERE     category_set_id = c.category_set_id
                               AND category_set_name = 'SHP_PURCHASING_TYPE';

                        IF (v_default_category > 0)
                        THEN
                           v_transaction_type := 'UPDATE';

                           SELECT default_category_id
                             INTO v_old_category_id
                             FROM mtl_category_sets
                            WHERE category_set_id = c.category_set_id;
                        ELSE
                           v_transaction_type := 'CREATE';
                           v_old_category_id := NULL;
                        END IF;

                        INSERT INTO mtl_item_categories_interface (item_number,
                                                                   category_set_id,
                                                                   category_id,
                                                                   old_category_id,
                                                                   organization_id,
                                                                   transaction_type,
                                                                   process_flag,
                                                                   set_process_id)
                             VALUES (ctf.item_code,
                                     c.category_set_id,
                                     c.category_id,
                                     v_old_category_id,
                                     v_mst_item_reg.organization_id,
                                     v_transaction_type,
                                     1,
                                     v_set_process_id);
                     EXCEPTION
                        WHEN OTHERS
                        THEN
                           v_err_msg :=
                                 'Item '
                              || ctf.item_code
                              || ': '
                              || SUBSTR (SQLERRM, 1, 2000)
                              || CHR (10);

                           UPDATE xxshp_inv_master_item_cat
                              SET status = 'E',
                                  MESSAGE = SUBSTR (MESSAGE || '#' || v_err_msg, 1, 2000),
                                  last_update_date = SYSDATE,
                                  last_updated_by = g_user_id,
                                  last_update_login = g_login_id
                            WHERE cat_id = c.cat_id;

                           v_err := 1;
                     END;
                  END LOOP;
               END IF;

               v_val := 1;
            END LOOP;

            IF (v_val = 1 AND v_err = 0)
            THEN
               v_request_id :=
                  fnd_request.submit_request (application   => 'INV',
                                              program       => 'INV_ITEM_CAT_ASSIGN_OI',
                                              description   => NULL,
                                              start_time    => NULL,
                                              sub_request   => FALSE,
                                              argument1     => v_set_process_id,
                                              argument2     => 1,
                                              argument3     => 1);
               COMMIT;

               --END IF;
               IF NVL (v_request_id, 0) = 0
               THEN
                  logf ('Interface Assign Category submission failed');
                  logf (SQLCODE || '-' || SQLERRM);
                  v_err := 1;
                  v_message :=
                     v_message || 'Interface Assign Category submission failed ' || SQLERRM || ';';
               ELSE
                  logf ('Request ID ' || v_request_id || ' has been submitted');
                  waitforrequest (v_request_id, v_status, v_err_msg);
               END IF;

               IF (UPPER (v_status) <> 'NORMAL')
               THEN
                  logf ('Interface Assign Category submission failed : ' || v_status);
                  logf (v_err_msg || ' - ' || SQLERRM);
                  v_err := 1;
                  v_message :=
                        v_message
                     || 'Interface Assign Category submission failed : '
                     || v_status
                     || ' - '
                     || v_err_msg
                     || ';';
               ELSE
                  logf ('Interface Assign Category completed : ' || v_status);
               END IF;
            ELSE
               logf ('No Data found');
            END IF;
         ELSE
            logf (
               'Data found in MTL_ITEM_CATEGORIES_INTERFACE for set_process_id:' || p_reg_hdr_id);
            v_err := 1;
            v_message :=
                  v_message
               || 'Data found in MTL_ITEM_CATEGORIES_INTERFACE for set_process_id:'
               || p_reg_hdr_id
               || ';';
         END IF;

         IF (v_err = 0)
         THEN
            UPDATE xxshp_inv_master_item_reg
               SET status_iface_item_cat = 'P'
             WHERE reg_hdr_id = p_reg_hdr_id;

            x_return := 0;
         ELSE
            x_return := 1;

            UPDATE xxshp_inv_master_item_reg
               SET status_iface_item_cat = 'E'
             WHERE reg_hdr_id = p_reg_hdr_id;
         /*DELETE mtl_item_categories_interface
          WHERE set_process_id = v_set_process_id;*/
         END IF;

         COMMIT;
      END IF;
   EXCEPTION
      WHEN OTHERS
      THEN
         logf ('Error on assign_item_category: ' || SQLERRM);
   END assign_item_category;

   PROCEDURE assign_item_subinv (p_reg_hdr_id IN NUMBER, x_return OUT NUMBER)
   /*
        Created by EY on 17-Mar-2017

        History Update:
   */
   IS
      v_val             NUMBER;
      v_val2            NUMBER;
      v_err             NUMBER := 0;
      v_error           NUMBER := 0;
      v_message         VARCHAR2 (1000);
      v_count           NUMBER := 0;
      v_split_kn_flag   VARCHAR2 (1);
      v_item_id         NUMBER;
      v_item_code       mtl_system_items_kfv.concatenated_segments%TYPE;
      v_validate        NUMBER;
   BEGIN
      SELECT COUNT (1)
        INTO v_validate
        FROM (SELECT *
                FROM xxshp_inv_master_item_reg
               WHERE     SPLIT_KN_FLAG = 'N'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND NVL (status_iface_subinv, 'E') = 'E'
              UNION ALL
              SELECT *
                FROM xxshp_inv_master_item_reg reg
               WHERE     SPLIT_KN_FLAG = 'Y'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND EXISTS
                            (SELECT 1
                               FROM xxshp_inv_master_item_kn kn
                              WHERE     NVL (status_iface_subinv, 'E') = 'E'
                                    AND kn.reg_hdr_id = reg.reg_hdr_id));


      IF (v_validate = 0)
      THEN
         logf ('No row to process');
      ELSE
      logf ('------------------------------------------------------------------------------');
        logf ('Start Interface Assign Item Subinventory');
         SELECT NVL (split_kn_flag, 'N'), item_id, item_code
           INTO v_split_kn_flag, v_item_id, v_item_code
           FROM xxshp_inv_master_item_reg
          WHERE reg_hdr_id = p_reg_hdr_id;

         IF v_split_kn_flag = 'N'
         THEN
            IF v_item_id IS NOT NULL
            THEN
               FOR c IN (SELECT *
                           FROM xxshp_inv_mst_item_subinv ximis
                          WHERE ximis.reg_hdr_id = p_reg_hdr_id)
               LOOP
                  SELECT COUNT (1)
                    INTO v_val
                    FROM mtl_item_sub_inventories
                   WHERE     inventory_item_id = v_item_id
                         AND secondary_inventory = c.subinv
                         AND organization_id = c.subinv_organization_id;

                  SELECT COUNT (1)
                    INTO v_val2
                    FROM mtl_secondary_inventories sub
                   WHERE     secondary_inventory_name = c.subinv
                         AND organization_id = c.subinv_organization_id
                         AND NVL (disable_date, SYSDATE + 1 / 24) > SYSDATE;

                  IF (v_val = 0 AND v_val2 > 0)
                  THEN
                     BEGIN
                        INSERT INTO mtl_item_sub_inventories (inventory_item_id,
                                                              organization_id,
                                                              secondary_inventory,
                                                              last_update_date,
                                                              last_updated_by,
                                                              creation_date,
                                                              created_by,
                                                              last_update_login,
                                                              inventory_planning_code)
                             VALUES (v_item_id,
                                     c.subinv_organization_id,
                                     c.subinv,
                                     SYSDATE,
                                     g_user_id,
                                     SYSDATE,
                                     g_user_id,
                                     g_login_id,
                                     6);
                     EXCEPTION
                        WHEN OTHERS
                        THEN
                           logf ('Error when inserting to mtl_item_sub_inventories ' || SQLERRM);
                           v_message :=
                                 v_message
                              || 'Error when inserting to mtl_item_sub_inventories '
                              || SQLERRM
                              || ';';
                           v_err := 1;
                     END;
                  ELSE
                     IF (v_val > 0)
                     THEN
                        logf (
                              'Item '
                           || v_item_code
                           || ' already assigned to restrict subinventory '
                           || c.subinv
                           || ' organization ID '
                           || c.subinv_organization_id);
                        v_message :=
                              'Item '
                           || v_item_code
                           || ' already assigned to restrict subinventory '
                           || c.subinv
                           || ' organization ID'
                           || c.subinv_organization_id;
                     END IF;

                     IF (v_val2 = 0)
                     THEN
                        v_err := 1;
                        logf (
                              'Subinventory '
                           || c.subinv
                           || ' is not assigned to organization ID'
                           || c.subinv_organization_id);
                        v_message :=
                              v_message
                           || 'Subinventory '
                           || c.subinv
                           || ' is not assigned to organization '
                           || c.subinv_organization_id
                           || ';';
                     END IF;
                  END IF;

                  v_count := 1;
               END LOOP;

               UPDATE xxshp_inv_master_item_reg
                  SET status_iface_subinv = 'P' /* Processed
                                                */
                                               ,
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE reg_hdr_id = p_reg_hdr_id;
            END IF;
         ELSE
            /* Pecah KN
             */
            FOR ckn IN (SELECT *
                          FROM xxshp_inv_master_item_kn kn
                         WHERE kn.reg_hdr_id = p_reg_hdr_id AND kn.item_id IS NOT NULL)
            LOOP
               FOR c IN (SELECT *
                           FROM xxshp_inv_mst_item_subinv ximis
                          WHERE ximis.reg_hdr_id = p_reg_hdr_id)
               LOOP
                  SELECT COUNT (1)
                    INTO v_val
                    FROM mtl_item_sub_inventories
                   WHERE     inventory_item_id = ckn.item_id
                         AND secondary_inventory = c.subinv
                         AND organization_id = c.subinv_organization_id;

                  SELECT COUNT (1)
                    INTO v_val2
                    FROM mtl_secondary_inventories sub
                   WHERE     secondary_inventory_name = c.subinv
                         AND organization_id = c.subinv_organization_id
                         AND NVL (disable_date, SYSDATE + 1 / 24) > SYSDATE;

                  IF (v_val = 0 AND v_val2 > 0)
                  THEN
                     BEGIN
                        INSERT INTO mtl_item_sub_inventories (inventory_item_id,
                                                              organization_id,
                                                              secondary_inventory,
                                                              last_update_date,
                                                              last_updated_by,
                                                              creation_date,
                                                              created_by,
                                                              last_update_login,
                                                              inventory_planning_code)
                             VALUES (ckn.item_id,
                                     c.subinv_organization_id,
                                     c.subinv,
                                     SYSDATE,
                                     g_user_id,
                                     SYSDATE,
                                     g_user_id,
                                     g_login_id,
                                     6);
                     EXCEPTION
                        WHEN OTHERS
                        THEN
                           logf ('Error when inserting to mtl_item_sub_inventories ' || SQLERRM);
                           v_message :=
                                 v_message
                              || 'Error when inserting to mtl_item_sub_inventories '
                              || SQLERRM
                              || ';';
                           v_err := 1;
                     END;
                  ELSE
                     IF (v_val > 0)
                     THEN
                        logf (
                              'Item '
                           || ckn.item_code
                           || ' already assigned to restrict subinventory '
                           || c.subinv
                           || ' organization ID '
                           || c.subinv_organization_id);
                        v_message :=
                              'Item '
                           || ckn.item_code
                           || ' already assigned to restrict subinventory '
                           || c.subinv
                           || ' organization ID'
                           || c.subinv_organization_id;
                     END IF;

                     IF (v_val2 = 0)
                     THEN
                        v_err := 1;
                        logf (
                              'Subinventory '
                           || c.subinv
                           || ' is not assigned to organization ID'
                           || c.subinv_organization_id);
                        v_message :=
                              v_message
                           || 'Subinventory '
                           || c.subinv
                           || ' is not assigned to organization '
                           || c.subinv_organization_id
                           || ';';
                     END IF;
                  END IF;
               END LOOP;

               UPDATE xxshp_inv_master_item_kn
                  SET status_iface_subinv = 'P' /* Processed
                                                */
                                               ,
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE kn_id = ckn.kn_id;

               v_count := 1;
            END LOOP;
         END IF;

         IF v_count = 0
         THEN
            logf ('No Data found');
         END IF;
        logf ('-------------------------------END Interface Assign Item Subinventory-----------------------------------------------');
         COMMIT;
      END IF;
   EXCEPTION
      WHEN OTHERS
      THEN
         logf ('Error on assign_item_subinv: ' || SQLERRM);
         x_return := 1;
   END assign_item_subinv;

   PROCEDURE create_master_item (p_reg_hdr_id IN NUMBER, x_return OUT NUMBER)
   /*
        Created by EY on 20-Mar-2017

        History Update:
   */
   IS
      v_request_id                     NUMBER;
      v_val                            NUMBER;
      v_status                         VARCHAR2 (100);
      v_errmsg                         VARCHAR2 (1000);
      v_message                        VARCHAR2 (1000);
      v_err                            NUMBER := 0;
      v_mst_item_reg                   xxshp_inv_master_item_reg%ROWTYPE;
      v_template_name                  mtl_item_templates.template_name%TYPE;
      v_trf_to_gl                      NUMBER;
      v_COSTING_ENABLED_FLAG           VARCHAR2 (1);
      v_INVENTORY_ASSET_FLAG           VARCHAR2 (1);
      v_PROCESS_COSTING_ENABLED_FLAG   VARCHAR2 (1);
      v_validate                       NUMBER;
      v_general_item                   VARCHAR2 (40);
   BEGIN
      fnd_global.apps_initialize (g_user_id, g_resp_id, g_resp_appl_id);
      mo_global.init ('INV');

      SELECT COUNT (1)
        INTO v_validate
        FROM (SELECT *
                FROM xxshp_inv_master_item_reg
               WHERE     SPLIT_KN_FLAG = 'N'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND NVL (status_iface_item_mst, 'E') = 'E'
              UNION ALL
              SELECT *
                FROM xxshp_inv_master_item_reg reg
               WHERE     SPLIT_KN_FLAG = 'Y'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND EXISTS
                            (SELECT 1
                               FROM xxshp_inv_master_item_kn kn
                              WHERE     NVL (status_iface_item_mst, 'E') = 'E'
                                    AND kn.reg_hdr_id = reg.reg_hdr_id));


      IF (v_validate = 0)
      THEN
         logf ('No row to process');
      ELSE
         SELECT *
           INTO v_mst_item_reg
           FROM (SELECT *
                   FROM xxshp_inv_master_item_reg
                  WHERE     SPLIT_KN_FLAG = 'N'
                        AND reg_hdr_id = p_reg_hdr_id
                        AND NVL (status_iface_item_mst, 'E') = 'E'
                 UNION ALL
                 SELECT *
                   FROM xxshp_inv_master_item_reg reg
                  WHERE     SPLIT_KN_FLAG = 'Y'
                        AND reg_hdr_id = p_reg_hdr_id
                        AND EXISTS
                               (SELECT 1
                                  FROM xxshp_inv_master_item_kn kn
                                 WHERE     NVL (status_iface_item_mst, 'E') = 'E'
                                       AND kn.reg_hdr_id = reg.reg_hdr_id));

         IF v_mst_item_reg.template_id IS NOT NULL
         THEN
            SELECT template_name
              INTO v_template_name
              FROM mtl_item_templates
             WHERE template_id = v_mst_item_reg.template_id;
         END IF;

         --delete previous error transaction
         DELETE mtl_system_items_interface
          WHERE     set_process_id = v_mst_item_reg.set_process_id
                AND global_attribute20 = 'XXSHP_INV_ITEM_MST_REG';

         SELECT COUNT (1)
           INTO v_val
           FROM mtl_system_items_interface
          WHERE set_process_id = v_mst_item_reg.set_process_id;

         IF (v_val = 0)
         THEN
            logf (
                  'Submit Interface Master Item for organization_id: '
               || v_mst_item_reg.organization_id);

            ---trf to GL = No
            SELECT COUNT (1)
              INTO v_trf_to_gl
              FROM mtl_parameters
             WHERE     GENERAL_LEDGER_UPDATE_CODE = 3
                   AND organization_id = v_mst_item_reg.organization_id;

            IF (v_trf_to_gl = 1)
            THEN
               v_COSTING_ENABLED_FLAG := 'N';
               v_INVENTORY_ASSET_FLAG := 'N';
               v_PROCESS_COSTING_ENABLED_FLAG := 'N';
            ELSE
               v_COSTING_ENABLED_FLAG := 'Y';
               v_INVENTORY_ASSET_FLAG := 'Y';
               v_PROCESS_COSTING_ENABLED_FLAG := 'Y';
            END IF;

            IF v_mst_item_reg.split_kn_flag = 'N'
            THEN
               SELECT COUNT (1)
                 INTO v_val
                 FROM xxshp_inv_master_item_reg
                WHERE     set_process_id = v_mst_item_reg.set_process_id
                      AND status_reg = g_inprocess_interface;

               IF (v_val > 0)
               THEN
                  v_err := 0;
                  v_message := NULL;

                  --1.2 updated by farry on 4-Dec-2017
                  BEGIN
                     SELECT segment1
                       INTO v_general_item
                       FROM mtl_system_items
                      WHERE     inventory_item_id = v_mst_item_reg.general_item_id
                            AND organization_id = v_mst_item_reg.general_item_org_id;
                  EXCEPTION
                     WHEN OTHERS
                     THEN
                        logf ('Error when get General Item: ' || SQLERRM);
                  END;


                  INSERT INTO mtl_system_items_interface (set_process_id,
                                                          organization_id,
                                                          segment1,
                                                          description,
                                                          primary_uom_code,
                                                          secondary_uom_code,
                                                          template_id,
                                                          transaction_type,
                                                          process_flag,
                                                          list_price_per_unit,
                                                          global_attribute18,
                                                          global_attribute19,
                                                          global_attribute20,
                                                          tracking_quantity_ind,
                                                          unit_weight,
                                                          weight_uom_code,
                                                          unit_volume,
                                                          volume_uom_code,
                                                          postprocessing_lead_time,
                                                          planner_code,
                                                          expense_account,
                                                          sales_account,
                                                          attribute_category,
                                                          attribute1,
                                                          attribute2,
                                                          attribute3,
                                                          attribute4,
                                                          attribute5,
                                                          attribute6,
                                                          attribute8,
                                                          attribute9,
                                                          attribute10,
                                                          attribute11,
                                                          attribute12,
                                                          attribute13,
                                                          attribute20,
                                                          attribute21,
                                                          --SECONDARY_DEFAULT_IND,ONT_PRICING_QTY_SOURCE,
                                                          created_by,
                                                          creation_date,
                                                          last_updated_by,
                                                          last_update_date,
                                                          last_update_login,
                                                          COSTING_ENABLED_FLAG,
                                                          INVENTORY_ASSET_FLAG,
                                                          PROCESS_COSTING_ENABLED_FLAG,
                                                          --1.2 updated by farry on 4-Dec-2017
                                                          FIXED_LOT_MULTIPLIER)
                          VALUES (
                                    v_mst_item_reg.set_process_id,
                                    v_mst_item_reg.organization_id,
                                    v_mst_item_reg.item_code,
                                    v_mst_item_reg.item_description,
                                    v_mst_item_reg.primary_uom,
                                    v_mst_item_reg.secondary_uom,
                                    v_mst_item_reg.template_id,
                                    'CREATE',
                                    1,
                                    NULL,
                                    'PARENT',
                                    v_mst_item_reg.reg_hdr_id,
                                    'XXSHP_INV_ITEM_MST_REG',
                                    v_mst_item_reg.tracking,
                                    v_mst_item_reg.unit_weight,
                                    v_mst_item_reg.uom_weight,
                                    v_mst_item_reg.unit_volume,
                                    v_mst_item_reg.uom_volume,
                                    DECODE (
                                       get_post_processing (
                                          TO_CHAR (v_mst_item_reg.organization_id),
                                          v_mst_item_reg.template_id),
                                       -1, v_mst_item_reg.post_processing,
                                       get_post_processing (
                                          TO_CHAR (v_mst_item_reg.organization_id),
                                          v_mst_item_reg.template_id)),
                                    v_mst_item_reg.planner,
                                    v_mst_item_reg.purchasing_expense_account,
                                    v_mst_item_reg.sales_account,
                                    'Direct',
                                    --v_mst_item_reg.general_item_id,
                                    --1.2 updated by farry on 4-Dec-2017
                                    v_general_item,
                                    v_template_name,
                                    v_mst_item_reg.lead_time_release,
                                    v_mst_item_reg.allergen,
                                    v_mst_item_reg.buffer_packaging,
                                    v_mst_item_reg.item_trial_id,
                                    v_mst_item_reg.reference_item_fg_id,
                                    v_mst_item_reg.weight_factor,
                                    v_mst_item_reg.shelf_life,
                                    NULL,                                           --PARENT_ITEM_KN
                                    NULL,
                                    --prev item code
                                    v_mst_item_reg.need_coa,
                                    v_mst_item_reg.pallet_size,
                                    v_mst_item_reg.packing_size,
                                    --NULL,'P',
                                    g_user_id,
                                    SYSDATE,
                                    g_user_id,
                                    SYSDATE,
                                    g_login_id,
                                    v_COSTING_ENABLED_FLAG,
                                    v_INVENTORY_ASSET_FLAG,
                                    v_PROCESS_COSTING_ENABLED_FLAG,
                                    --1.2 updated by farry on 4-Dec-2017
                                    v_mst_item_reg.FIXED_LOT_MULTIPLIER);
               ELSE
                  logf ('No Data found ' || SQLERRM);
               END IF;
            ELSIF v_mst_item_reg.split_kn_flag = 'Y'
            THEN
               FOR ckn IN (SELECT *
                             FROM xxshp_inv_master_item_kn kn
                            WHERE kn.reg_hdr_id = p_reg_hdr_id AND kn.item_id IS NULL)
               LOOP
                  v_val := 1;


                  --1.2 updated by farry on 4-Dec-2017
                  BEGIN
                     SELECT segment1
                       INTO v_general_item
                       FROM mtl_system_items
                      WHERE     inventory_item_id = v_mst_item_reg.general_item_id
                            AND organization_id = v_mst_item_reg.general_item_org_id;
                  EXCEPTION
                     WHEN OTHERS
                     THEN
                        logf ('Error when get General Item: ' || SQLERRM);
                  END;



                  INSERT INTO mtl_system_items_interface (set_process_id,
                                                          organization_id,
                                                          segment1,
                                                          description,
                                                          primary_uom_code,
                                                          secondary_uom_code,
                                                          template_id,
                                                          transaction_type,
                                                          process_flag,
                                                          list_price_per_unit,
                                                          global_attribute18,
                                                          global_attribute19,
                                                          global_attribute20,
                                                          tracking_quantity_ind,
                                                          unit_weight,
                                                          weight_uom_code,
                                                          unit_volume,
                                                          volume_uom_code,
                                                          postprocessing_lead_time,
                                                          planner_code,
                                                          expense_account,
                                                          sales_account,
                                                          attribute_category,
                                                          attribute1,
                                                          attribute2,
                                                          attribute3,
                                                          attribute4,
                                                          attribute5,
                                                          attribute6,
                                                          attribute8,
                                                          attribute9,
                                                          attribute10,
                                                          attribute11,
                                                          attribute12,
                                                          attribute13,
                                                          attribute20,
                                                          attribute21,
                                                          created_by,
                                                          creation_date,
                                                          last_updated_by,
                                                          last_update_date,
                                                          last_update_login,
                                                          COSTING_ENABLED_FLAG,
                                                          INVENTORY_ASSET_FLAG,
                                                          PROCESS_COSTING_ENABLED_FLAG,
                                                          --1.2 updated by farry on 4-Dec-2017
                                                          FIXED_LOT_MULTIPLIER)
                          VALUES (
                                    v_mst_item_reg.set_process_id,
                                    v_mst_item_reg.organization_id,
                                    ckn.item_code,
                                    ckn.item_description,
                                    v_mst_item_reg.primary_uom,
                                    v_mst_item_reg.secondary_uom,
                                    v_mst_item_reg.template_id,
                                    'CREATE',
                                    1,
                                    NULL,
                                    'KN',
                                    v_mst_item_reg.reg_hdr_id,
                                    'XXSHP_INV_ITEM_MST_REG',
                                    v_mst_item_reg.tracking,
                                    v_mst_item_reg.unit_weight,
                                    v_mst_item_reg.uom_weight,
                                    v_mst_item_reg.unit_volume,
                                    v_mst_item_reg.uom_volume,
                                    --v_mst_item_reg.post_processing,
                                    DECODE (
                                       get_post_processing (
                                          TO_CHAR (v_mst_item_reg.organization_id),
                                          v_mst_item_reg.template_id),
                                       -1, v_mst_item_reg.post_processing,
                                       get_post_processing (
                                          TO_CHAR (v_mst_item_reg.organization_id),
                                          v_mst_item_reg.template_id)),
                                    v_mst_item_reg.planner,
                                    v_mst_item_reg.purchasing_expense_account,
                                    v_mst_item_reg.sales_account,
                                    'Direct',
                                    --v_mst_item_reg.general_item_id,
                                    --1.2 updated by farry on 4-Dec-2017
                                    v_general_item,
                                    v_template_name,
                                    v_mst_item_reg.lead_time_release,
                                    v_mst_item_reg.allergen,
                                    v_mst_item_reg.buffer_packaging,
                                    v_mst_item_reg.item_trial_id,
                                    v_mst_item_reg.reference_item_fg_id,
                                    v_mst_item_reg.weight_factor,
                                    v_mst_item_reg.shelf_life,
                                    v_mst_item_reg.item_code,                       --PARENT_ITEM_KN
                                    NULL,
                                    --prev item code
                                    v_mst_item_reg.need_coa,
                                    v_mst_item_reg.pallet_size,
                                    v_mst_item_reg.packing_size,
                                    g_user_id,
                                    SYSDATE,
                                    g_user_id,
                                    SYSDATE,
                                    g_login_id,
                                    v_COSTING_ENABLED_FLAG,
                                    v_INVENTORY_ASSET_FLAG,
                                    v_PROCESS_COSTING_ENABLED_FLAG,
                                    --1.2 updated by farry on 4-Dec-2017
                                    v_mst_item_reg.FIXED_LOT_MULTIPLIER);
               END LOOP;
            END IF;

            /*Unstandard*/
            FOR custd IN (SELECT *
                            FROM xxshp_inv_master_item_unstd_v ustd
                           WHERE ustd.reg_hdr_id = p_reg_hdr_id AND ustd.item_id IS NULL)
            LOOP
               v_val := 1;
               v_template_name := NULL;

               IF custd.template_id IS NOT NULL
               THEN
                  SELECT template_name
                    INTO v_template_name
                    FROM mtl_item_templates
                   WHERE template_id = custd.template_id;
               END IF;

               --1.2 updated by farry on 4-Dec-2017
               BEGIN
                  SELECT segment1
                    INTO v_general_item
                    FROM mtl_system_items
                   WHERE     inventory_item_id = v_mst_item_reg.general_item_id
                         AND organization_id = v_mst_item_reg.general_item_org_id;
               EXCEPTION
                  WHEN OTHERS
                  THEN
                     logf ('Error when get General Item: ' || SQLERRM);
               END;



               INSERT INTO mtl_system_items_interface (set_process_id,
                                                       organization_id,
                                                       segment1,
                                                       description,
                                                       primary_uom_code,
                                                       secondary_uom_code,
                                                       template_id,
                                                       transaction_type,
                                                       process_flag,
                                                       list_price_per_unit,
                                                       global_attribute18,
                                                       global_attribute19,
                                                       global_attribute20,
                                                       tracking_quantity_ind,
                                                       unit_weight,
                                                       weight_uom_code,
                                                       unit_volume,
                                                       volume_uom_code,
                                                       postprocessing_lead_time,
                                                       planner_code,
                                                       expense_account,
                                                       sales_account,
                                                       attribute_category,
                                                       attribute1,
                                                       attribute2,
                                                       attribute3,
                                                       attribute4,
                                                       attribute5,
                                                       attribute6,
                                                       attribute8,
                                                       attribute9,
                                                       attribute10,
                                                       attribute11,
                                                       attribute12,
                                                       attribute13,
                                                       attribute20,
                                                       attribute21,
                                                       created_by,
                                                       creation_date,
                                                       last_updated_by,
                                                       last_update_date,
                                                       last_update_login,
                                                       COSTING_ENABLED_FLAG,
                                                       INVENTORY_ASSET_FLAG,
                                                       PROCESS_COSTING_ENABLED_FLAG,
                                                       --1.2 updated by farry on 4-Dec-2017
                                                       FIXED_LOT_MULTIPLIER)
                       VALUES (
                                 v_mst_item_reg.set_process_id,
                                 v_mst_item_reg.organization_id,
                                 custd.item_code,
                                 custd.item_description,
                                 custd.uom,
                                 NULL,
                                 custd.template_id,
                                 'CREATE',
                                 1,
                                 NULL,
                                 'UNSTD',
                                 v_mst_item_reg.reg_hdr_id,
                                 'XXSHP_INV_ITEM_MST_REG',
                                 v_mst_item_reg.tracking,
                                 v_mst_item_reg.unit_weight,
                                 v_mst_item_reg.uom_weight,
                                 v_mst_item_reg.unit_volume,
                                 v_mst_item_reg.uom_volume,
                                 --v_mst_item_reg.post_processing,
                                 DECODE (
                                    get_post_processing (TO_CHAR (v_mst_item_reg.organization_id),
                                                         custd.template_id),
                                    -1, v_mst_item_reg.post_processing,
                                    get_post_processing (TO_CHAR (v_mst_item_reg.organization_id),
                                                         custd.template_id)),
                                 v_mst_item_reg.planner,
                                 v_mst_item_reg.purchasing_expense_account,
                                 v_mst_item_reg.sales_account,
                                 'Direct',
                                 --v_mst_item_reg.general_item_id,
                                 --1.2 updated by farry on 4-Dec-2017
                                 v_general_item,
                                 v_template_name,
                                 v_mst_item_reg.lead_time_release,
                                 v_mst_item_reg.allergen,
                                 v_mst_item_reg.buffer_packaging,
                                 v_mst_item_reg.item_trial_id,
                                 custd.reference_item_fg_id,
                                 v_mst_item_reg.weight_factor,
                                 v_mst_item_reg.shelf_life,
                                 NULL,
                                 --PARENT_ITEM_KN
                                 NULL,
                                 --prev item code
                                 v_mst_item_reg.need_coa,
                                 v_mst_item_reg.pallet_size,
                                 v_mst_item_reg.packing_size,
                                 g_user_id,
                                 SYSDATE,
                                 g_user_id,
                                 SYSDATE,
                                 g_login_id,
                                 v_COSTING_ENABLED_FLAG,
                                 v_INVENTORY_ASSET_FLAG,
                                 v_PROCESS_COSTING_ENABLED_FLAG,
                                 --1.2 updated by farry on 4-Dec-2017
                                 v_mst_item_reg.FIXED_LOT_MULTIPLIER);
            END LOOP;

            /*TollFee*/
            FOR ctf IN (SELECT *
                          FROM xxshp_inv_master_item_toll_v tf
                         WHERE tf.reg_hdr_id = p_reg_hdr_id AND tf.item_id IS NULL)
            LOOP
               v_val := 1;
               v_template_name := NULL;

               IF ctf.template_id IS NOT NULL
               THEN
                  SELECT template_name
                    INTO v_template_name
                    FROM mtl_item_templates
                   WHERE template_id = ctf.template_id;
               END IF;


               --1.2 updated by farry on 4-Dec-2017
               BEGIN
                  SELECT segment1
                    INTO v_general_item
                    FROM mtl_system_items
                   WHERE     inventory_item_id = v_mst_item_reg.general_item_id
                         AND organization_id = v_mst_item_reg.general_item_org_id;
               EXCEPTION
                  WHEN OTHERS
                  THEN
                     logf ('Error when get General Item: ' || SQLERRM);
               END;



               INSERT INTO mtl_system_items_interface (set_process_id,
                                                       organization_id,
                                                       segment1,
                                                       description,
                                                       primary_uom_code,
                                                       secondary_uom_code,
                                                       template_id,
                                                       transaction_type,
                                                       process_flag,
                                                       list_price_per_unit,
                                                       global_attribute18,
                                                       global_attribute19,
                                                       global_attribute20,
                                                       tracking_quantity_ind,
                                                       unit_weight,
                                                       weight_uom_code,
                                                       unit_volume,
                                                       volume_uom_code,
                                                       postprocessing_lead_time,
                                                       planner_code,
                                                       expense_account,
                                                       sales_account,
                                                       attribute_category,
                                                       attribute1,
                                                       attribute2,
                                                       attribute3,
                                                       attribute4,
                                                       attribute5,
                                                       attribute6,
                                                       attribute8,
                                                       attribute9,
                                                       attribute10,
                                                       attribute11,
                                                       attribute12,
                                                       attribute13,
                                                       attribute20,
                                                       attribute21,
                                                       created_by,
                                                       creation_date,
                                                       last_updated_by,
                                                       last_update_date,
                                                       last_update_login,
                                                       COSTING_ENABLED_FLAG,
                                                       INVENTORY_ASSET_FLAG,
                                                       PROCESS_COSTING_ENABLED_FLAG,
                                                       --1.2 updated by farry on 4-Dec-2017
                                                       FIXED_LOT_MULTIPLIER)
                       VALUES (
                                 v_mst_item_reg.set_process_id,
                                 v_mst_item_reg.organization_id,
                                 ctf.item_code,
                                 ctf.item_description,
                                 ctf.uom,
                                 NULL,
                                 ctf.template_id,
                                 'CREATE',
                                 1,
                                 NULL,
                                 'TOLLFEE',
                                 v_mst_item_reg.reg_hdr_id,
                                 'XXSHP_INV_ITEM_MST_REG',
                                 v_mst_item_reg.tracking,
                                 v_mst_item_reg.unit_weight,
                                 v_mst_item_reg.uom_weight,
                                 v_mst_item_reg.unit_volume,
                                 v_mst_item_reg.uom_volume,
                                 --v_mst_item_reg.post_processing,
                                 DECODE (
                                    get_post_processing (TO_CHAR (v_mst_item_reg.organization_id),
                                                         ctf.template_id),
                                    -1, v_mst_item_reg.post_processing,
                                    get_post_processing (TO_CHAR (v_mst_item_reg.organization_id),
                                                         ctf.template_id)),
                                 v_mst_item_reg.planner,
                                 v_mst_item_reg.purchasing_expense_account,
                                 v_mst_item_reg.sales_account,
                                 'Direct',
                                 --v_mst_item_reg.general_item_id,
                                 --1.2 updated by farry on 4-Dec-2017
                                 v_general_item,
                                 v_template_name,
                                 v_mst_item_reg.lead_time_release,
                                 v_mst_item_reg.allergen,
                                 v_mst_item_reg.buffer_packaging,
                                 v_mst_item_reg.item_trial_id,
                                 ctf.reference_item_fg_id,
                                 v_mst_item_reg.weight_factor,
                                 v_mst_item_reg.shelf_life,
                                 NULL,
                                 --PARENT_ITEM_KN
                                 NULL,
                                 --prev item code
                                 v_mst_item_reg.need_coa,
                                 v_mst_item_reg.pallet_size,
                                 v_mst_item_reg.packing_size,
                                 g_user_id,
                                 SYSDATE,
                                 g_user_id,
                                 SYSDATE,
                                 g_login_id,
                                 v_COSTING_ENABLED_FLAG,
                                 v_INVENTORY_ASSET_FLAG,
                                 v_PROCESS_COSTING_ENABLED_FLAG,
                                 --1.2 updated by farry on 4-Dec-2017
                                 v_mst_item_reg.FIXED_LOT_MULTIPLIER);
            END LOOP;
         ELSE
            logf (
                  'Data found in MTL_SYSTEM_ITEMS_INTERFACE for set_process_id:'
               || v_mst_item_reg.set_process_id);
            v_err := 1;
            v_message :=
                  v_message
               || 'Data found in MTL_SYSTEM_ITEMS_INTERFACE for set_process_id:'
               || v_mst_item_reg.set_process_id
               || ';';
         END IF;

         IF v_val = 1
         THEN
            v_request_id :=
               fnd_request.submit_request (
                  application   => 'INV',
                  program       => 'INCOIN',
                  description   => 'Process ID #' || v_mst_item_reg.set_process_id,
                  start_time    => NULL,
                  sub_request   => FALSE,
                  argument1     => v_mst_item_reg.organization_id,                -- Organization id
                  argument2     => 1,                                           -- All organizations
                  argument3     => 1,                                              -- Validate Items
                  argument4     => 1,                                               -- Process Items
                  argument5     => 1,                                       -- Delete Processed Rows
                  argument6     => v_mst_item_reg.set_process_id,      -- Process Set (Null for All)
                  argument7     => 1,                                      -- Create or Update Items
                  argument8     => 1                                            -- Gather Statistics
                                    );
            COMMIT;

            IF NVL (v_request_id, 0) = 0
            THEN
               logf ('Import Items submission failed ' || SQLERRM);
               logf (SQLCODE || '-' || SQLERRM);
               v_err := 1;
               v_message := v_message || 'Import Items submission failed ' || SQLERRM || ';';
            ELSE
               logf ('Request ID ' || v_request_id || ' has been submitted');
               waitforrequest (v_request_id, v_status, v_errmsg);
            END IF;

            IF (UPPER (v_status) <> 'NORMAL')
            THEN
               logf ('Import Items submission failed : ' || v_status);
               logf (v_errmsg || ' - ' || SQLERRM);
               v_err := 1;
               v_message :=
                     v_message
                  || 'Import Items submission failed : '
                  || v_status
                  || ' - '
                  || v_errmsg
                  || ';';

               FOR a
                  IN (SELECT error_message
                        FROM mtl_interface_errors
                       WHERE     table_name = 'MTL_SYSTEM_ITEMS_INTERFACE'
                             AND request_id = v_request_id)
               LOOP
                  v_message := v_message || a.error_message || ';';
                  logf ('err ' || a.error_message);
               END LOOP;
            ELSE
               logf ('Import Items submission completed : ' || v_status);
            END IF;
         END IF;

         FOR x
            IN (SELECT 'PARENT' item_type, msi.inventory_item_id, msi.segment1
                  FROM mtl_system_items msi, xxshp_inv_master_item_reg ximir
                 WHERE     msi.segment1 = ximir.item_code
                       AND msi.organization_id = v_mst_item_reg.organization_id
                       AND ximir.reg_hdr_id = p_reg_hdr_id
                UNION
                SELECT 'KN' item_type, msi.inventory_item_id, msi.segment1
                  FROM mtl_system_items msi, xxshp_inv_master_item_kn ximik
                 WHERE     msi.segment1 = ximik.item_code
                       AND msi.organization_id = v_mst_item_reg.organization_id
                       AND ximik.reg_hdr_id = p_reg_hdr_id
                UNION
                SELECT 'UNSTD' item_type, msi.inventory_item_id, msi.segment1
                  FROM mtl_system_items msi, xxshp_inv_master_item_unstd ximiu
                 WHERE     msi.segment1 = ximiu.item_code
                       AND msi.organization_id = v_mst_item_reg.organization_id
                       AND ximiu.reg_hdr_id = p_reg_hdr_id
                UNION
                SELECT 'TOLLFEE' item_type, msi.inventory_item_id, msi.segment1
                  FROM mtl_system_items msi, xxshp_inv_master_item_toll ximit
                 WHERE     msi.segment1 = ximit.item_code
                       AND msi.organization_id = v_mst_item_reg.organization_id
                       AND ximit.reg_hdr_id = p_reg_hdr_id)
         LOOP
            IF x.item_type = 'PARENT'
            THEN
               UPDATE xxshp_inv_master_item_reg
                  SET item_id = x.inventory_item_id,
                      status_iface_item_mst = 'S',
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE item_code = x.segment1;
            ELSIF x.item_type = 'KN'
            THEN
               UPDATE xxshp_inv_master_item_kn
                  SET item_id = x.inventory_item_id,
                      status_iface_item_mst = 'S',
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE item_code = x.segment1;
            ELSIF x.item_type = 'UNSTD'
            THEN
               UPDATE xxshp_inv_master_item_unstd
                  SET item_id = x.inventory_item_id,
                      status_iface_item_mst = 'S',
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE item_code = x.segment1;
            ELSIF x.item_type = 'TOLLFEE'
            THEN
               UPDATE xxshp_inv_master_item_toll
                  SET item_id = x.inventory_item_id,
                      status_iface_item_mst = 'S',
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE item_code = x.segment1;
            END IF;

            logf ('Inventory Item ID: ' || x.inventory_item_id || ' for Item Code ' || x.segment1);
         END LOOP;

         FOR y
            IN (SELECT msii.segment1, mie.error_message, msii.global_attribute18 item_type
                  FROM mtl_system_items_interface msii, mtl_interface_errors mie
                 WHERE msii.transaction_id = mie.transaction_id AND msii.request_id = v_request_id)
         LOOP
            IF y.item_type = 'PARENT'
            THEN
               UPDATE xxshp_inv_master_item_reg
                  SET status_iface_item_mst = 'E',
                      message_iface_item_mst =
                         SUBSTR (message_iface_item_mst || y.error_message || CHR (10), 1, 2000),
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE item_code = y.segment1;
            ELSIF y.item_type = 'KN'
            THEN
               UPDATE xxshp_inv_master_item_kn
                  SET status_iface_item_mst = 'E',
                      message_iface_item_mst =
                         SUBSTR (message_iface_item_mst || y.error_message || CHR (10), 1, 2000),
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE item_code = y.segment1;
            ELSIF y.item_type = 'UNSTD'
            THEN
               UPDATE xxshp_inv_master_item_unstd
                  SET status_iface_item_mst = 'E',
                      message_iface_item_mst =
                         SUBSTR (message_iface_item_mst || y.error_message || CHR (10), 1, 2000),
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE item_code = y.segment1;
            ELSIF y.item_type = 'TOLLFEE'
            THEN
               UPDATE xxshp_inv_master_item_toll
                  SET status_iface_item_mst = 'E',
                      message_iface_item_mst =
                         SUBSTR (message_iface_item_mst || y.error_message || CHR (10), 1, 2000),
                      last_update_date = SYSDATE,
                      last_updated_by = g_user_id,
                      last_update_login = g_login_id
                WHERE item_code = y.segment1;
            END IF;
         END LOOP;

         DELETE mtl_interface_errors mie
          WHERE EXISTS
                   (SELECT 1
                      FROM mtl_system_items_interface msii
                     WHERE     msii.global_attribute20 = 'XXSHP_INV_ITEM_MST_REG'
                           AND msii.global_attribute19 = TO_CHAR (p_reg_hdr_id)
                           AND msii.transaction_id = mie.transaction_id
                           AND request_id = v_request_id);

         DELETE mtl_system_items_interface
          WHERE     global_attribute20 = 'XXSHP_INV_ITEM_MST_REG'
                AND global_attribute19 = TO_CHAR (p_reg_hdr_id)
                AND request_id = v_request_id;

         COMMIT;
      END IF;

      IF (v_err = 0)
      THEN
         x_return := 0;
      ELSE
         x_return := 1;
      END IF;
   EXCEPTION
      WHEN OTHERS
      THEN
         logf ('Error on create_master_item : ' || SQLERRM);
         x_return := 1;
   END create_master_item;

   PROCEDURE assign_org_item (p_reg_hdr_id NUMBER, x_return OUT NUMBER)
   /*
        Created by EY on 20-Mar-2017

        History Update:
   */
   IS
      v_mst_item_reg                   xxshp_inv_master_item_reg%ROWTYPE;
      v_val                            NUMBER;
      v_request_id                     NUMBER;
      v_status                         VARCHAR2 (100);
      v_errmsg                         VARCHAR2 (1000);
      v_err                            NUMBER := 0;
      v_message                        VARCHAR2 (1000);
      v_planner_CODE                   VARCHAR2 (10);
      v_trf_to_gl                      NUMBER;
      v_COSTING_ENABLED_FLAG           VARCHAR2 (1);
      v_INVENTORY_ASSET_FLAG           VARCHAR2 (1);
      v_PROCESS_COSTING_ENABLED_FLAG   VARCHAR2 (1);
      v_validate                       NUMBER;
      v_oth                            NUMBER;
   BEGIN
      fnd_global.apps_initialize (g_user_id, g_resp_id, g_resp_appl_id);
      mo_global.init ('INV');


      SELECT COUNT (1)
        INTO v_validate
        FROM (SELECT *
                FROM xxshp_inv_master_item_reg
               WHERE     SPLIT_KN_FLAG = 'N'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND NVL (status_iface_org_asgn, 'E') = 'E'
              UNION ALL
              SELECT *
                FROM xxshp_inv_master_item_reg reg
               WHERE     SPLIT_KN_FLAG = 'Y'
                     AND reg_hdr_id = p_reg_hdr_id
                     AND EXISTS
                            (SELECT 1
                               FROM xxshp_inv_master_item_kn kn
                              WHERE     NVL (status_iface_org_asgn, 'E') = 'E'
                                    AND kn.reg_hdr_id = reg.reg_hdr_id));


      IF (v_validate = 0)
      THEN
         logf ('No row to process');
      ELSE
         logf ('Submit Interface Assign Organization Item');

         SELECT *
           INTO v_mst_item_reg
           FROM xxshp_inv_master_item_reg
          WHERE reg_hdr_id = p_reg_hdr_id;

         --delete previous error transaction
         DELETE mtl_system_items_interface
          WHERE     set_process_id = v_mst_item_reg.set_process_id
                AND global_attribute20 = 'XXSHP_INV_ITEM_MST_REG';

         SELECT COUNT (1)
           INTO v_val
           FROM mtl_system_items_interface
          WHERE set_process_id = v_mst_item_reg.set_process_id;

         FOR corg
            IN (SELECT planner, asgn_organization_id
                  FROM xxshp_inv_master_item_org ximio, xxshp_inv_master_item_reg ximir
                 WHERE     ximio.reg_hdr_id = p_reg_hdr_id
                       AND ximir.reg_hdr_id = p_reg_hdr_id
                       AND ximir.item_id IS NOT NULL)
         LOOP
            BEGIN
               SELECT planner_code
                 INTO v_planner_code
                 FROM mtl_planners
                WHERE planner_code = corg.planner AND organization_id = corg.asgn_organization_id;
            EXCEPTION
               WHEN OTHERS
               THEN
                  logf (
                        'Error when get Planner:'
                     || corg.planner
                     || ' organization_id:'
                     || corg.asgn_organization_id);
                  v_val := 1;
            END;
         END LOOP;



         IF (v_val = 0)
         THEN
            FOR corg IN (SELECT *
                           FROM xxshp_inv_master_item_org ximio
                          WHERE ximio.reg_hdr_id = p_reg_hdr_id)
            LOOP
               v_val := 1;

               ---trf to GL = No
               SELECT COUNT (1)
                 INTO v_trf_to_gl
                 FROM mtl_parameters
                WHERE     GENERAL_LEDGER_UPDATE_CODE = 3
                      AND organization_id = corg.asgn_organization_id;

               IF (v_trf_to_gl = 1)
               THEN
                  v_COSTING_ENABLED_FLAG := 'N';
                  v_INVENTORY_ASSET_FLAG := 'N';
                  v_PROCESS_COSTING_ENABLED_FLAG := 'N';
               ELSE
                  v_COSTING_ENABLED_FLAG := 'Y';
                  v_INVENTORY_ASSET_FLAG := 'Y';
                  v_PROCESS_COSTING_ENABLED_FLAG := 'Y';
               END IF;

               FOR c IN (SELECT *
                           FROM xxshp_inv_master_item_reg ximir
                          WHERE ximir.reg_hdr_id = p_reg_hdr_id AND ximir.item_id IS NOT NULL)
               LOOP
                  v_planner_code := c.PLANNER;

                  INSERT INTO mtl_system_items_interface (inventory_item_id,
                                                          organization_id,
                                                          process_flag,
                                                          set_process_id,
                                                          transaction_type,
                                                          PLANNER_CODE,
                                                          COSTING_ENABLED_FLAG,
                                                          INVENTORY_ASSET_FLAG,
                                                          PROCESS_COSTING_ENABLED_FLAG,
                                                          postprocessing_lead_time)
                          VALUES (
                                    c.item_id,
                                    corg.asgn_organization_id,
                                    1,
                                    v_mst_item_reg.set_process_id,
                                    'CREATE',
                                    v_planner_code,
                                    v_COSTING_ENABLED_FLAG,
                                    v_INVENTORY_ASSET_FLAG,
                                    v_PROCESS_COSTING_ENABLED_FLAG,
                                    DECODE (
                                       get_post_processing (TO_CHAR (corg.asgn_organization_id),
                                                            c.template_id),
                                       -1, c.post_processing,
                                       get_post_processing (TO_CHAR (corg.asgn_organization_id),
                                                            c.template_id)));
               END LOOP;

               FOR ckn
                  IN (SELECT ximik.*, ximir.post_processing, ximir.template_id
                        FROM xxshp_inv_master_item_kn ximik, xxshp_inv_master_item_reg ximir
                       WHERE     ximik.reg_hdr_id = ximir.reg_hdr_id
                             AND ximik.reg_hdr_id = p_reg_hdr_id
                             AND ximik.item_id IS NOT NULL)
               LOOP
                  INSERT INTO mtl_system_items_interface (inventory_item_id,
                                                          organization_id,
                                                          process_flag,
                                                          set_process_id,
                                                          transaction_type,
                                                          PLANNER_CODE,
                                                          COSTING_ENABLED_FLAG,
                                                          INVENTORY_ASSET_FLAG,
                                                          PROCESS_COSTING_ENABLED_FLAG,
                                                          postprocessing_lead_time)
                          VALUES (
                                    ckn.item_id,
                                    corg.asgn_organization_id,
                                    1,
                                    v_mst_item_reg.set_process_id,
                                    'CREATE',
                                    v_PLANNER_CODE,
                                    v_COSTING_ENABLED_FLAG,
                                    v_INVENTORY_ASSET_FLAG,
                                    v_PROCESS_COSTING_ENABLED_FLAG,
                                    DECODE (
                                       get_post_processing (TO_CHAR (corg.asgn_organization_id),
                                                            ckn.template_id),
                                       -1, ckn.post_processing,
                                       get_post_processing (TO_CHAR (corg.asgn_organization_id),
                                                            ckn.template_id)));
               END LOOP;

               FOR custd
                  IN (SELECT ximiu.*, ximir.post_processing
                        FROM xxshp_inv_master_item_unstd ximiu, xxshp_inv_master_item_reg ximir
                       WHERE     ximiu.reg_hdr_id = ximir.reg_hdr_id
                             AND ximiu.reg_hdr_id = p_reg_hdr_id
                             AND ximiu.item_id IS NOT NULL)
               LOOP
                  INSERT INTO mtl_system_items_interface (inventory_item_id,
                                                          organization_id,
                                                          process_flag,
                                                          set_process_id,
                                                          transaction_type,
                                                          PLANNER_CODE,
                                                          COSTING_ENABLED_FLAG,
                                                          INVENTORY_ASSET_FLAG,
                                                          PROCESS_COSTING_ENABLED_FLAG,
                                                          postprocessing_lead_time)
                          VALUES (
                                    custd.item_id,
                                    corg.asgn_organization_id,
                                    1,
                                    v_mst_item_reg.set_process_id,
                                    'CREATE',
                                    v_PLANNER_CODE,
                                    v_COSTING_ENABLED_FLAG,
                                    v_INVENTORY_ASSET_FLAG,
                                    v_PROCESS_COSTING_ENABLED_FLAG,
                                    DECODE (
                                       get_post_processing (TO_CHAR (corg.asgn_organization_id),
                                                            custd.template_id),
                                       -1, custd.post_processing,
                                       get_post_processing (TO_CHAR (corg.asgn_organization_id),
                                                            custd.template_id)));
               END LOOP;
            END LOOP;

            FOR ctf
               IN (SELECT ximit.*, ximir.post_processing
                     FROM xxshp_inv_master_item_toll ximit, xxshp_inv_master_item_reg ximir
                    WHERE     ximit.reg_hdr_id = ximir.reg_hdr_id
                          AND ximit.reg_hdr_id = p_reg_hdr_id
                          AND ximit.item_id IS NOT NULL)
            LOOP
               v_val := 1;

               ---trf to GL = No
               SELECT COUNT (1)
                 INTO v_trf_to_gl
                 FROM mtl_parameters
                WHERE GENERAL_LEDGER_UPDATE_CODE = 3 AND organization_code = 'OTH';

               IF (v_trf_to_gl = 1)
               THEN
                  v_COSTING_ENABLED_FLAG := 'N';
                  v_INVENTORY_ASSET_FLAG := 'N';
                  v_PROCESS_COSTING_ENABLED_FLAG := 'N';
               ELSE
                  v_COSTING_ENABLED_FLAG := 'Y';
                  v_INVENTORY_ASSET_FLAG := 'Y';
                  v_PROCESS_COSTING_ENABLED_FLAG := 'Y';
               END IF;

               BEGIN
                  SELECT organization_id
                    INTO v_oth
                    FROM mtl_parameters
                   WHERE organization_code = 'OTH';
               EXCEPTION
                  WHEN OTHERS
                  THEN
                     logf ('Error when get organization_id ' || SQLERRM);
               END;


               INSERT INTO mtl_system_items_interface (inventory_item_id,
                                                       organization_code,
                                                       process_flag,
                                                       set_process_id,
                                                       transaction_type,
                                                       PLANNER_CODE,
                                                       COSTING_ENABLED_FLAG,
                                                       INVENTORY_ASSET_FLAG,
                                                       PROCESS_COSTING_ENABLED_FLAG,
                                                       postprocessing_lead_time)
                       VALUES (
                                 ctf.item_id,
                                 'OTH',
                                 1,
                                 v_mst_item_reg.set_process_id,
                                 'CREATE',
                                 v_PLANNER_CODE,
                                 v_COSTING_ENABLED_FLAG,
                                 v_INVENTORY_ASSET_FLAG,
                                 v_PROCESS_COSTING_ENABLED_FLAG,
                                 DECODE (get_post_processing (TO_CHAR (v_oth), ctf.template_id),
                                         -1, ctf.post_processing,
                                         get_post_processing (TO_CHAR (v_oth), ctf.template_id)));
            END LOOP;
         ELSE
            logf (
                  'Data found in MTL_SYSTEM_ITEMS_INTERFACE for set_process_id:'
               || v_mst_item_reg.set_process_id);
            v_err := 1;
            v_message :=
                  v_message
               || 'Data found in MTL_SYSTEM_ITEMS_INTERFACE for set_process_id:'
               || v_mst_item_reg.set_process_id
               || ';';
         END IF;

         IF v_val = 1
         THEN
            v_request_id :=
               fnd_request.submit_request (
                  application   => 'INV',
                  program       => 'INCOIN',
                  description   => 'Assign Org Proses ID#' || v_mst_item_reg.set_process_id,
                  start_time    => NULL,
                  sub_request   => FALSE,
                  argument1     => 1,
                  --v_mst_item_reg.organization_id,                                            -- Organization id
                  argument2     => 1,                                           -- All organizations
                  argument3     => 1,                                              -- Validate Items
                  argument4     => 1,                                               -- Process Items
                  argument5     => 1,                                       -- Delete Processed Rows
                  argument6     => v_mst_item_reg.set_process_id,      -- Process Set (Null for All)
                  argument7     => 1,                                      -- Create or Update Items
                  argument8     => 1                                            -- Gather Statistics
                                    );
            COMMIT;

            IF NVL (v_request_id, 0) = 0
            THEN
               logf ('Import Items submission failed ' || SQLERRM);
               logf (SQLCODE || '-' || SQLERRM);
               v_err := 1;
               v_message := v_message || 'Import Items submission failed ' || SQLERRM || ';';
            ELSE
               logf ('Request ID ' || v_request_id || ' has been submitted');
               waitforrequest (v_request_id, v_status, v_errmsg);
            END IF;

            IF (UPPER (v_status) <> 'NORMAL')
            THEN
               logf ('Import Items submission failed : ' || v_status);
               logf (v_errmsg || ' - ' || SQLERRM);
               v_err := 1;
               v_message :=
                     v_message
                  || 'Import Items submission failed : '
                  || v_status
                  || ' - '
                  || v_errmsg
                  || ';';

               FOR a
                  IN (SELECT error_message
                        FROM mtl_interface_errors
                       WHERE     table_name = 'MTL_SYSTEM_ITEMS_INTERFACE'
                             AND request_id = v_request_id)
               LOOP
                  v_message := v_message || a.error_message || ';';
                  logf ('err ' || a.error_message);
               END LOOP;
            ELSE
               logf ('Import Items submission completed : ' || v_status);

               FOR x
                  IN (SELECT 'PARENT' item_type,
                             msi.organization_id,
                             msi.inventory_item_id,
                             msi.segment1
                        FROM mtl_system_items msi, xxshp_inv_master_item_reg ximir
                       WHERE     msi.segment1 = ximir.item_code
                             AND msi.organization_id <> v_mst_item_reg.organization_id
                             AND ximir.reg_hdr_id = p_reg_hdr_id
                      UNION
                      SELECT 'KN' item_type,
                             msi.organization_id,
                             msi.inventory_item_id,
                             msi.segment1
                        FROM mtl_system_items msi, xxshp_inv_master_item_kn ximik
                       WHERE     msi.segment1 = ximik.item_code
                             AND msi.organization_id <> v_mst_item_reg.organization_id
                             AND ximik.reg_hdr_id = p_reg_hdr_id
                      UNION
                      SELECT 'UNSTD' item_type,
                             msi.organization_id,
                             msi.inventory_item_id,
                             msi.segment1
                        FROM mtl_system_items msi, xxshp_inv_master_item_unstd ximiu
                       WHERE     msi.segment1 = ximiu.item_code
                             AND msi.organization_id <> v_mst_item_reg.organization_id
                             AND ximiu.reg_hdr_id = p_reg_hdr_id
                      UNION
                      SELECT 'TOLLFEE' item_type,
                             msi.organization_id,
                             msi.inventory_item_id,
                             msi.segment1
                        FROM mtl_system_items msi, xxshp_inv_master_item_toll ximit
                       WHERE     msi.segment1 = ximit.item_code
                             AND msi.organization_id <> v_mst_item_reg.organization_id
                             AND ximit.reg_hdr_id = p_reg_hdr_id)
               LOOP
                  UPDATE xxshp_inv_master_item_org
                     SET MESSAGE =
                            SUBSTR (MESSAGE || 'Item ' || x.segment1 || ' : S' || CHR (10),
                                    1,
                                    2000),
                         last_update_date = SYSDATE,
                         last_updated_by = g_user_id,
                         last_update_login = g_login_id
                   WHERE asgn_organization_id = x.organization_id;

                  IF x.item_type = 'PARENT'
                  THEN
                     UPDATE xxshp_inv_master_item_reg
                        SET status_iface_org_asgn = 'P',
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE item_code = x.segment1;
                  ELSIF x.item_type = 'KN'
                  THEN
                     UPDATE xxshp_inv_master_item_kn
                        SET status_iface_org_asgn = 'P',
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE item_code = x.segment1;
                  ELSIF x.item_type = 'UNSTD'
                  THEN
                     UPDATE xxshp_inv_master_item_unstd
                        SET status_iface_org_asgn = 'P',
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE item_code = x.segment1;
                  ELSIF x.item_type = 'TOLLFEE'
                  THEN
                     UPDATE xxshp_inv_master_item_toll
                        SET status_iface_org_asgn = 'P',
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE item_code = x.segment1;
                  END IF;

                  logf ('Item Code ' || x.segment1 || ' on oganization ID ' || x.organization_id);
               END LOOP;

               FOR y
                  IN (SELECT msii.segment1, mie.error_message, msii.global_attribute18 item_type
                        FROM mtl_system_items_interface msii, mtl_interface_errors mie
                       WHERE     msii.transaction_id = mie.transaction_id
                             AND msii.request_id = v_request_id)
               LOOP
                  IF y.item_type = 'PARENT'
                  THEN
                     UPDATE xxshp_inv_master_item_reg
                        SET message_iface_org_asgn =
                               SUBSTR (message_iface_org_asgn || y.error_message || CHR (10),
                                       1,
                                       2000),
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE item_code = y.segment1;
                  ELSIF y.item_type = 'KN'
                  THEN
                     UPDATE xxshp_inv_master_item_kn
                        SET message_iface_org_asgn =
                               SUBSTR (message_iface_org_asgn || y.error_message || CHR (10),
                                       1,
                                       2000),
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE item_code = y.segment1;
                  ELSIF y.item_type = 'UNSTD'
                  THEN
                     UPDATE xxshp_inv_master_item_unstd
                        SET message_iface_org_asgn =
                               SUBSTR (message_iface_org_asgn || y.error_message || CHR (10),
                                       1,
                                       2000),
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE item_code = y.segment1;
                  ELSIF y.item_type = 'TOLLFEE'
                  THEN
                     UPDATE xxshp_inv_master_item_toll
                        SET message_iface_org_asgn =
                               SUBSTR (message_iface_org_asgn || y.error_message || CHR (10),
                                       1,
                                       2000),
                            last_update_date = SYSDATE,
                            last_updated_by = g_user_id,
                            last_update_login = g_login_id
                      WHERE item_code = y.segment1;
                  END IF;
               END LOOP;
            END IF;
         END IF;

         DELETE mtl_interface_errors mie
          WHERE request_id = v_request_id;

         DELETE mtl_system_items_interface
          WHERE request_id = v_request_id;

         COMMIT;
      END IF;

      IF (v_err = 0)
      THEN
         x_return := 0;
      ELSE
         x_return := 1;
      END IF;
   EXCEPTION
      WHEN OTHERS
      THEN
         logf ('Error on assign_org_item : ' || SQLERRM);
         x_return := 1;
   END assign_org_item;

   PROCEDURE submit_items_interface (p_errbuf          OUT VARCHAR2,
                                     p_retcode         OUT NUMBER,
                                     p_reg_hdr_id   IN     NUMBER)
   /*
        Created by EY on 17-Mar-2017

        History Update:
   */
   IS
      v_return   NUMBER := 0;
      v_error    NUMBER := 0;
      v_validate NUMBER := 0;
   BEGIN
      logf ('Start Interface Master Item');
      create_master_item (p_reg_hdr_id, v_return);

      IF (v_return = 1)
      THEN
         v_error := 1;
      ELSE
         logf ('------------------------------------------------------------------------------');
         logf ('Start Interface Assign Item Category');
         assign_item_category (p_reg_hdr_id, v_return);

         logf ('------------------------------------------------------------------------------');
         logf ('Start Interface Assign Organization Item');
         assign_org_item (p_reg_hdr_id, v_return);

         IF (v_return = 1)
         THEN
            -- Start Added Fajrin 2017-10-12 --
            
            SELECT COUNT (1)
                INTO v_validate
                FROM (SELECT *
                        FROM xxshp_inv_master_item_reg
                       WHERE     SPLIT_KN_FLAG = 'N'
                             AND reg_hdr_id = p_reg_hdr_id
                             AND NVL (status_iface_subinv, 'E') = 'E'
                  UNION ALL
                  SELECT *
                    FROM xxshp_inv_master_item_reg reg
                   WHERE     SPLIT_KN_FLAG = 'Y'
                         AND reg_hdr_id = p_reg_hdr_id
                         AND EXISTS
                                (SELECT 1
                                   FROM xxshp_inv_master_item_kn kn
                                  WHERE     NVL (status_iface_subinv, 'E') = 'E'
                                        AND kn.reg_hdr_id = reg.reg_hdr_id));
                                    
            IF (v_validate = 0)
                THEN
                    logf ('No row to process');
                    v_error := 1;
            else
                 logf ('------------------------------------------------------------------------------');
                 logf ('Start Program Assign Item to Restrict Subinventory');
                  assign_item_subinv (p_reg_hdr_id, v_return);
            end if;
            
            -- end Added Fajrin 2017-10-12 --
            --v_error := 1;
         ELSE
            logf ('------------------------------------------------------------------------------');
            logf ('Start Program Assign Item to Restrict Subinventory');
            assign_item_subinv (p_reg_hdr_id, v_return);

            IF (v_return = 1)
            THEN
               v_error := 1;
            END IF;
         END IF;
      END IF;

      COMMIT;
   EXCEPTION
      WHEN OTHERS
      THEN
         p_retcode := 2;
         logf ('Error on submit_items_interface : ' || SQLERRM);
   END submit_items_interface;

   PROCEDURE fg_tf_email_notif (p_reg_hdr_id NUMBER)
   IS
      v_hdr_id       NUMBER := p_reg_hdr_id;
      v_short_name   VARCHAR2 (50) := 'XXSHP_INV_ITEM_MST_REG';
      v_pref_it      VARCHAR2 (100) := 'XXX';
      v_pref_fg      VARCHAR2 (100) := 'XXX';
      v_body         VARCHAR2 (32000);
      v_sender       VARCHAR2 (100) := 'oracle.erp@kalbenutritionals.com';
      v_email        VARCHAR2 (1000);
      v_subject      VARCHAR2 (100);
      v_errmsg       VARCHAR2 (1000);

      CURSOR c1 (
         p_hdr_id        NUMBER,
         p_short_name    VARCHAR2)
      IS
           SELECT SUBSTR (msi.segment1, -3) org,
                  msi.item_type,
                  msi.segment1 item_code,
                  msi.description,
                  msi.primary_uom_code,
                  msi.creation_date start_date,
                  asp.vendor_name || '-' || assa.vendor_site_code supplier,
                  mcv.segment1,
                  mcv.segment4,
                  CASE
                     WHEN mcv.segment4 <> 'LOCAL'
                     THEN
                        'FG Export'
                     WHEN mcv.segment4 = 'LOCAL' AND mcv.segment1 = 'HOSPITAL DIET NUTRITIONAL'
                     THEN
                        'FG Ethical'
                     WHEN mcv.segment4 = 'LOCAL'
                     THEN
                        'FG Local'
                  END
                     fg_type
             FROM mtl_system_items msi,
                  mtl_parameters mp,
                  ap_suppliers asp,
                  ap_supplier_sites_all assa,
                  mtl_item_categories_v mcv,
                  mtl_parameters mmp
            WHERE     msi.item_type IN ('FINISHED GOOD', 'TOLL FEE')
                  AND SUBSTR (msi.segment1, -3) = mp.organization_code(+)
                  AND msi.global_attribute19 = p_hdr_id
                  AND msi.global_attribute20 = p_short_name
                  AND msi.organization_id = mmp.organization_id
                  AND mmp.master_organization_id = mmp.organization_id
                  AND asp.vendor_id(+) = SUBSTR (mp.attribute7, 1, INSTR (mp.attribute7, '-') - 1)
                  AND assa.vendor_site_id(+) = SUBSTR (mp.attribute7, INSTR (mp.attribute7, '-') + 1)
                  AND mcv.category_set_name(+) = 'SHP_MAR' || CHR (38) || 'FA_PRODUCT_LINE'
                  AND msi.inventory_item_id = mcv.inventory_item_id(+)
                  AND msi.organization_id = mcv.organization_id(+)
                  AND (   (msi.item_type = 'TOLL FEE' AND mp.organization_code IS NOT NULL)
                       OR (    msi.item_type = 'FINISHED GOOD'
                           AND CASE
                                  WHEN mcv.segment4 <> 'LOCAL'
                                  THEN
                                     'FG Export'
                                  WHEN     mcv.segment4 = 'LOCAL'
                                       AND mcv.segment1 = 'HOSPITAL DIET NUTRITIONAL'
                                  THEN
                                     'FG Ethical'
                                  WHEN mcv.segment4 = 'LOCAL'
                                  THEN
                                     'FG Local'
                               END
                                  IS NOT NULL))
         ORDER BY msi.item_type DESC, msi.segment1, fg_type;
   BEGIN
      FOR x IN c1 (v_hdr_id, v_short_name)
      LOOP
         IF v_pref_it <> x.item_type
         THEN
            IF v_pref_it != 'XXX'
            THEN
               IF v_pref_it = 'TOLL FEE'
               THEN
                  v_email := fnd_profile.VALUE ('XXSHP_' || UPPER (REPLACE (v_pref_it, ' ', '_')));
                  v_subject := 'Toll Fee Item Notification';
                  v_body := v_body || '</table>';
                  v_errmsg := NULL;
                  xxshp_mail_pkg.send_email (v_sender,
                                             v_email,
                                             v_subject,
                                             v_body,
                                             v_errmsg);
                  logf ('Send Toll Fee Item Notification:' || v_errmsg);
                  --Init FG
                  v_body := NULL;
                  v_body := '<table border="1">
                            <tr>
                            <td><b>Item Type</b></td>
                            <td><b>Item</b></td>
                            <td><b>Description</b></td>
                            <td><b>Primary UoM</b></td>
                            <td><b>Start Date</b></td>
                            <td><b>FG Type</b></td>
                            </tr>';
               END IF;
            ELSE                                                                     --Init Toll Fee
               v_body := NULL;
               v_body := '<table border="1">
                            <tr>
                            <td><b>Organization</b></td>
                            <td><b>Item Type</b></td>
                            <td><b>Item</b></td>
                            <td><b>Description</b></td>
                            <td><b>Primary UoM</b></td>
                            <td><b>Start Date</b></td>
                            <td><b>Supplier-Supplier Site</b></td>
                            </tr>';
            END IF;

            v_pref_it := x.item_type;
         END IF;

         IF x.item_type = 'FINISHED GOOD' AND v_pref_fg <> x.fg_type
         THEN
            IF v_pref_it != 'XXX'
            THEN
               v_email := fnd_profile.VALUE ('XXSHP_' || UPPER (REPLACE (v_pref_fg, ' ', '_')));
               v_subject := v_pref_fg || ' Item Notification';
               v_body := v_body || '</table>';
               v_errmsg := NULL;
               xxshp_mail_pkg.send_email (v_sender,
                                          v_email,
                                          v_subject,
                                          v_body,
                                          v_errmsg);
               logf ('Send ' || v_pref_fg || ' Item Notification:' || v_errmsg);
               --Init FG
               v_body := NULL;
               v_body := '<table border="1">
                            <tr>
                            <td><b>Item Type</b></td>
                            <td><b>Item</b></td>
                            <td><b>Description</b></td>
                            <td><b>Primary UoM</b></td>
                            <td><b>Start Date</b></td>
                            <td><b>FG Type</b></td>
                            </tr>';
            END IF;

            v_pref_fg := x.fg_type;
         END IF;

         IF x.item_type = 'FINISHED GOOD'
         THEN
            v_body :=
                  v_body
               || '<tr>
                            <td>'
               || x.item_type
               || '</td>
                            <td>'
               || x.item_code
               || '</td>
                            <td>'
               || x.description
               || '</td>
                            <td>'
               || x.primary_uom_code
               || '</td>
                            <td>'
               || x.start_date
               || '</td>
                            <td>'
               || x.fg_type
               || '</td>';
         ELSIF x.item_type = 'TOLL FEE'
         THEN
            v_body :=
                  v_body
               || '<tr>
                            <td>'
               || x.org
               || '</td>
                            <td>'
               || x.item_type
               || '</td>
                            <td>'
               || x.item_code
               || '</td>
                            <td>'
               || x.description
               || '</td>
                            <td>'
               || x.primary_uom_code
               || '</td>
                            <td>'
               || x.start_date
               || '</td>
                            <td>'
               || x.supplier
               || '</td>
                            </tr>';
         END IF;
      END LOOP;

      IF v_pref_it = 'TOLL FEE'
      THEN
         v_email := fnd_profile.VALUE ('XXSHP_' || UPPER (REPLACE (v_pref_it, ' ', '_')));
         v_subject := 'Toll Fee Item Notification';
         v_body := v_body || '</table>';
         v_errmsg := NULL;


         xxshp_mail_pkg.send_email (v_sender,
                                    v_email,
                                    v_subject,
                                    v_body,
                                    v_errmsg);
         logf ('Send Toll Fee Item Notification:' || v_errmsg);
      ELSIF v_pref_fg LIKE 'FG%'
      THEN
         v_email := fnd_profile.VALUE ('XXSHP_' || UPPER (REPLACE (v_pref_fg, ' ', '_')));
         v_subject := v_pref_fg || ' Item Notification';
         v_body := v_body || '</table>';
         v_errmsg := NULL;

         xxshp_mail_pkg.send_email (v_sender,
                                    v_email,
                                    v_subject,
                                    v_body,
                                    v_errmsg);
         logf ('Send ' || v_pref_fg || ' Item Notification:' || v_errmsg);
      END IF;
   EXCEPTION
      WHEN OTHERS
      THEN
         ROLLBACK;
         logf ('Unexpected Error :' || SQLERRM);
         logf (DBMS_UTILITY.format_error_backtrace);
   END fg_tf_email_notif;

   PROCEDURE main_process (p_errbuf OUT VARCHAR2, p_retcode OUT NUMBER, p_reg_hdr_id IN NUMBER)
   /*
        Created by EY on 14-Mar-2017

        History Update:
   */
   IS
      v_set_process_id   NUMBER;
      v_val              NUMBER;
      v_validate         NUMBER;
            v_item_id         NUMBER;
      v_lob               VARCHAR2 (4);
      v_tipe              VARCHAR2 (5);
      v_countmd       NUMBER;
      v_countakasia  NUMBER;
      v_template_name VARCHAR(50);
   BEGIN
      /**
      related to group of item ifaces
      */

      ---check if item already created in MTL_SYSTEM_ITEMS
      /*SELECT COUNT (1)
        INTO v_val
        FROM mtl_system_items msi, xxshp_inv_master_item_reg ximir
       WHERE msi.segment1 = ximir.item_code AND msi.organization_id = ximir.organization_id AND ximir.reg_hdr_id = p_reg_hdr_id;

      IF (v_val > 0)
      THEN
         logf ('Item already created before');
      ELSE*/
      logf ('-----------Create Item, Assign Org, Assign Categories and Restrict Subinv----------');

      SELECT mtl_system_items_intf_sets_s.NEXTVAL INTO v_set_process_id FROM DUAL;

      UPDATE xxshp_inv_master_item_reg
         SET set_process_id = v_set_process_id,
             status_reg = g_inprocess_interface,
             request_id = g_request_id
       WHERE reg_hdr_id = p_reg_hdr_id;

      COMMIT;
      submit_items_interface (p_errbuf, p_retcode, p_reg_hdr_id);
      --
      logf ('-----------Create UOM Conversion----------');
      create_uom_conversion (p_reg_hdr_id);
      logf ('-----------Create ASL Attributes----------');
      create_asl_attributes (p_reg_hdr_id);
      logf ('-----------Create Manufacturer Part Numbers----------');
      create_mfg_part_numbers (p_reg_hdr_id);
      logf ('-----------Create Bill of Distribution----------');
      create_bill_of_dist (p_reg_hdr_id);
      logf ('-----------Notification Item Registration----------');
      fg_tf_email_notif (p_reg_hdr_id);
      logf ('------------------------------------------------------------------------------');

      SELECT COUNT (1)
        INTO v_val
        FROM mtl_system_items msi, xxshp_inv_master_item_reg ximir
       WHERE msi.segment1 LIKE ximir.item_code || '%' --AND msi.organization_id = ximir.organization_id
                                                     AND ximir.reg_hdr_id = p_reg_hdr_id;

      SELECT COUNT (1)
        INTO v_validate
        FROM (SELECT 1
                FROM xxshp_inv_master_item_reg
               WHERE     reg_hdr_id = p_reg_hdr_id
                     AND SPLIT_KN_FLAG = 'N'
                     AND (   STATUS_IFACE_ASL = 'E'
                          OR STATUS_IFACE_BOD = 'E'
                          OR STATUS_IFACE_ITEM_CAT = 'E'
                          OR STATUS_IFACE_ITEM_MST = 'E'
                          OR STATUS_IFACE_MANUFACTUR = 'E'
                          OR NVL (STATUS_IFACE_ORG_ASGN, 'E') = 'E'
                          OR STATUS_IFACE_PART_NUM = 'E'
                          OR STATUS_IFACE_SRC_RULE = 'E'
                          OR STATUS_IFACE_SUBINV = 'E'
                          OR STATUS_IFACE_UOM_CONV = 'E')
              UNION ALL
              SELECT 1
                FROM xxshp_inv_master_item_reg reg, xxshp_inv_master_item_kn kn
               WHERE     reg.reg_hdr_id = kn.reg_hdr_id
                     AND reg.reg_hdr_id = p_reg_hdr_id
                     AND SPLIT_KN_FLAG = 'Y'
                     AND (reg.STATUS_IFACE_BOD = 'E' OR reg.STATUS_IFACE_ITEM_CAT = 'E')
                     AND (   kn.STATUS_IFACE_ASL = 'E'
                          --OR kn.STATUS_IFACE_BOD = 'E'
                          --OR kn.STATUS_IFACE_ITEM_CAT = 'E'
                          OR kn.STATUS_IFACE_ITEM_MST = 'E'
                          OR kn.STATUS_IFACE_MANUFACTUR = 'E'
                          OR NVL (kn.STATUS_IFACE_ORG_ASGN, 'E') = 'E'
                          OR kn.STATUS_IFACE_PART_NUM = 'E'
                          OR kn.STATUS_IFACE_SRC_RULE = 'E'
                          OR kn.STATUS_IFACE_SUBINV = 'E'
                          OR kn.STATUS_IFACE_UOM_CONV = 'E'));

      IF (v_val > 0 AND v_validate = 0)
      THEN
         logf ('Item created successfully');

         UPDATE xxshp_inv_master_item_reg
            SET status_reg = g_success
          WHERE reg_hdr_id = p_reg_hdr_id;
          
           select template_name into v_template_name from mtl_item_templates
           where template_id =  (select template_id from xxshp_inv_master_item_reg where reg_hdr_id = p_reg_hdr_id and rownum <=1);
           
           logf ('template_name : ' || v_template_name );
          
          -- Added Fajrin 2018-07-14
            IF v_template_name IN ('FGSA BUY','FGSA MAKE','PM') THEN
            
                    select count(certificate_md_num), count(akasia_num)  into v_countmd, v_countakasia
                    from xxshp_inv_manufacturers xim, xxshp_inv_mfg_part_numbers mpn
                    where xim.mfg_id = mpn.mfg_id
                    and reg_hdr_id = p_reg_hdr_id;
                    
                    logf ('v_countmd : ' || v_countmd );
                    logf ('v_countakasia : ' || v_countakasia );
                    
                    select inventory_item_id into v_item_id from mtl_system_items
                    where organization_id = 84
                    and segment1 =  (select item_code from xxshp_inv_master_item_reg where reg_hdr_id = p_reg_hdr_id and rownum <=1);
                    
                    logf ('v_item_id : ' || v_item_id );
                    
                IF v_template_name = 'PM' THEN
                
                logf ('v_template_name in PM : ' || v_template_name );
                    IF v_countakasia > 0 THEN
                            IF v_countmd = 0 THEN
                                change_status(v_item_id, 84, 'Need MD');
                                UPDATE xxshp_inv_master_item_reg SET need_md = 'Y' WHERE reg_hdr_id = p_reg_hdr_id; COMMIT;
                                logf ('end change status in PM');
                            END IF;
                    END IF;     
                ELSE
                    select segment3, substr(segment4, instr(segment4,'_', -1, 1)+1)
                    into v_lob,v_tipe
                    from xxshp_inv_master_item_cat xim, mtl_categories mca
                    where xim.category_id = mca.category_id
                    and category_set_id = 1100000042 
                    and item_type = 'PARENT'
                    and reg_hdr_id = p_reg_hdr_id;
                    
                    logf ('v_lob : ' || v_lob );
                    logf ('v_tipe : ' || v_tipe );
                    
                    IF v_lob IN ('KNG','KN1','KN2','KN3','KN4') and v_tipe = '2A000' THEN
                            IF v_countmd = 0 THEN
                                change_status(v_item_id, 84, 'Need MD');
                                UPDATE xxshp_inv_master_item_reg SET need_md = 'Y' WHERE reg_hdr_id = p_reg_hdr_id; COMMIT;
                                logf ('end change status in FG');
                            END IF;
                    END IF;
                END IF;
            END IF;
            --- end Added Fajrin 2018-07-14

         COMMIT;
      ELSE
         UPDATE xxshp_inv_master_item_reg
            SET status_reg = g_error_interface
          WHERE reg_hdr_id = p_reg_hdr_id;

         COMMIT;
         p_retcode := 2;
      END IF;

      logf ('End of program');
   --END IF;
   END main_process;
   
   PROCEDURE change_status(p_item_id NUMBER, p_org_id NUMBER, p_status VARCHAR)
    IS
      l_item_table       EGO_Item_PUB.Item_Tbl_Type;
      x_item_table      EGO_Item_PUB.Item_Tbl_Type;
      x_return_status  VARCHAR2(1);
      x_msg_count     NUMBER(10);
      x_msg_data       VARCHAR2(1000);
      x_message_list   Error_Handler.Error_Tbl_Type;
    BEGIN
        --Apps Initialize
        fnd_global.apps_initialize (g_user_id, g_resp_id, g_resp_appl_id);
        mo_global.init ('INV');

          -- Item definition
          l_item_table(1).Transaction_Type := 'UPDATE';
          l_item_table(1).Inventory_item_id := p_item_id;
          l_item_table(1).Organization_id := p_org_id;
          l_item_table(1).Inventory_item_status_code := p_status;

        -- Calling procedure EGO_ITEM_PUB.Process_Items
          EGO_ITEM_PUB.Process_Items(
        --Input Parameters
                                     p_api_version   => 1.0,
                                     p_init_msg_list => FND_API.g_TRUE,
                                     p_commit        => FND_API.g_TRUE,
                                     p_Item_Tbl      => l_item_table,

        --Output Parameters
                                     x_Item_Tbl      => x_item_table,
                                     x_return_status => x_return_status,
                                     x_msg_count     => x_msg_count);

          DBMS_OUTPUT.PUT_LINE('Items updated Status ==>' || x_return_status);
          logf('Items updated Status ==>' || x_return_status);

          IF (x_return_status = FND_API.G_RET_STS_SUCCESS) THEN
            FOR i IN 1 .. x_item_table.COUNT LOOP
              DBMS_OUTPUT.PUT_LINE('Inventory Item Id :' ||to_char(x_item_table(i).Inventory_Item_Id));
              DBMS_OUTPUT.PUT_LINE('Organization Id   :' ||to_char(x_item_table(i).Organization_Id));
              logf('Inventory Item Id :' ||to_char(x_item_table(i).Inventory_Item_Id));
              logf('Organization Id   :' ||to_char(x_item_table(i).Organization_Id));
            END LOOP;
          ELSE
            DBMS_OUTPUT.PUT_LINE('Error Messages :');
            logf('Error Messages :');
            Error_Handler.GET_MESSAGE_LIST(x_message_list => x_message_list);
            FOR i IN 1 .. x_message_list.COUNT LOOP
              DBMS_OUTPUT.PUT_LINE(x_message_list(i).message_text);
              logf(x_message_list(i).message_text);
            END LOOP;
          END IF;
     END;
END xxshp_inv_master_item_reg_pkg;
/
