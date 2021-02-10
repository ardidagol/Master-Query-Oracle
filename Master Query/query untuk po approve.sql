PROCEDURE po_auto_approve (po_number VARCHAR2)
   IS
      v_item_key   VARCHAR2 (100);
      var_pathid   NUMBER;
      var_fromid   NUMBER;
      var_toid     NUMBER;

      CURSOR c_po_details
      IS
         SELECT pha.po_header_id,
                pha.org_id,
                pha.segment1,
                pha.agent_id,
                pdt.document_subtype,
                pdt.document_type_code,
                pha.authorization_status
           FROM apps.po_headers_all pha, apps.po_document_types_all pdt
          WHERE     pha.type_lookup_code = pdt.document_subtype
                AND pha.org_id = pdt.org_id
                AND pdt.document_type_code = 'PO'
                AND authorization_status IN ('INCOMPLETE',
                                             'REQUIRES REAPPROVAL',
                                             'REJECTED')
                AND segment1 = po_number;   -- Enter the Purchase Order Number
   BEGIN
      fnd_global.apps_initialize (user_id        => g_user_id,
                                  resp_id        => g_resp_id,
                                  resp_appl_id   => g_resp_appl_id);

      FOR p_rec IN c_po_details
      LOOP
         mo_global.init (p_rec.document_type_code);
         mo_global.set_policy_context ('S', p_rec.org_id);

         SELECT    p_rec.po_header_id
                || '-'
                || TO_CHAR (po_wf_itemkey_s.NEXTVAL)
           INTO v_item_key
           FROM DUAL;

         SELECT position_structure_id, person_id, superior_person_id
           INTO var_pathid, var_fromid, var_toid
           FROM xxshp_hr_pos_hierarchy_v
          WHERE person_id = p_rec.agent_id;

         logf (
               'Calling po_reqapproval_init1.start_wf_process for po_id=> '
            || p_rec.segment1);

         po_reqapproval_init1.start_wf_process (
            itemtype                 => 'POAPPRV',
            itemkey                  => v_item_key,
            workflowprocess          => 'POAPPRV_TOP',
            actionoriginatedfrom     => 'PO_FORM',
            documentid               => p_rec.po_header_id,    -- po_header_id
            documentnumber           => p_rec.segment1, -- Purchase Order Number
            preparerid               => p_rec.agent_id,   -- Buyer/Preparer_id
            documenttypecode         => p_rec.document_type_code,       --'PO'
            documentsubtype          => p_rec.document_subtype,   --'STANDARD'
            submitteraction          => 'APPROVE',
            forwardtoid              => NULL,
            forwardfromid            => NULL,
            defaultapprovalpathid    => var_pathid,
            note                     => NULL,
            printflag                => 'N',
            faxflag                  => 'N',
            faxnumber                => NULL,
            emailflag                => 'N',
            emailaddress             => NULL,
            createsourcingrule       => 'N',
            releasegenmethod         => 'N',
            updatesourcingrule       => 'N',
            massupdatereleases       => 'N',
            retroactivepricechange   => 'N',
            orgassignchange          => 'N',
            communicatepricechange   => 'N',
            p_background_flag        => 'N',
            p_initiator              => NULL,
            p_xml_flag               => NULL,
            fpdsngflag               => 'N',
            p_source_type_code       => NULL);

         COMMIT;
         logf ('The PO which is Approved Now =>' || p_rec.segment1);
      END LOOP;
   END;