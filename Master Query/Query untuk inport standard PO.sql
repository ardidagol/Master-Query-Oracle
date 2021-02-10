 mo_global.init ('PO');
      mo_global.set_policy_context ('S', '82');                 -- Pass ORG_ID
      apps.fnd_global.apps_initialize (user_id        => g_user_id, -- Pass user id
                                       resp_id        => g_resp_id, -- Pass responsibility id
                                       resp_appl_id   => g_resp_appl_id -- Pass responsibility application id
                                                                       );

      v_iface_request_id :=
         fnd_request.submit_request (
            application   => 'PO',
            program       => 'POXPOPDOI',
            description   =>    'XXSHP '
                             || v_batch_id
                             || '-PR-'
                             || p_pr_number
                             || '/'
                             || TO_CHAR (SYSDATE, 'DD-MON-RRRR'),
            start_time    => SYSDATE + 2 / 24 / 60 / 60,
            sub_request   => FALSE,
            argument1     => NULL,    --pin_default_buyer_id, -- Default Buyer
            argument2     => 'STANDARD',                      -- Document Type
            argument3     => NULL,                         -- Document SubType
            argument4     => 'N',                    -- Create or Update Items
            argument5     => 'N',                     -- Create Sourcing Rules
            argument6     => 'INCOMPLETE', --piv_approval_status, -- Approval Status
            argument7     => NULL,                       -- Release Generation
            argument8     => v_batch_id,                           -- Batch Id
            argument9     => g_org_id, --NULL,             --pin_org_id, -- Operating Unit
            argument10    => NULL,                         -- Global Agreement
            argument11    => NULL,                    -- Enable Sourcing Level
            argument12    => NULL,                           -- Sourcing Level
            argument13    => NULL,                           -- Inv Org Enable
            argument14    => NULL                    -- Inventory Organization
                                 );