global class CustomerTierDiscountPostHook 
    implements RevSignaling.SignalingApexProcessor { 
 
    global RevSignaling.TransactionResponse execute( 
        RevSignaling.TransactionRequest request 
    ) { 
 
        String contextId = request.ctxInstanceId; 
 
        Context.IndustriesContext context = 
            new Context.IndustriesContext(); 
 
        /* 
         * Query SalesTransaction and SalesTransactionItem. 
         */ 
        Map<String, Object> queryInput = 
            new Map<String, Object>{ 
                'contextId' => contextId, 
                'tags' => new List<String>{ 
                    'SalesTransaction', 
                    'SalesTransactionItem' 
                } 
            }; 
 
        Map<String, Object> queryOutput = 
            context.queryTags(queryInput); 
 
        Map<String, Object> queryResult = 
            (Map<String, Object>) queryOutput.get( 
                'queryResult' 
            ); 
 
        if (queryResult == null) { 
            return successResponse(); 
        } 
 
        /* 
         * Get SalesTransaction. 
         */ 
        List<Object> salesTransactions = 
            (List<Object>) queryResult.get( 
                'SalesTransaction' 
            ); 
 
        if (salesTransactions == null || 
            salesTransactions.isEmpty()) { 
 
            return successResponse(); 
        } 
 
        Map<String, Object> salesTransaction = 
            (Map<String, Object>) salesTransactions[0]; 
 
        Map<String, Object> transactionTagValue = 
            (Map<String, Object>) 
                salesTransaction.get('tagValue'); 
 
        if (transactionTagValue == null) { 
            return successResponse(); 
        } 
 
        /* 
         * Get Customer Tier. 
         */ 
        String customerTier = 
            getTagValue( 
                transactionTagValue, 
                'Customer_Tier__c' 
            ); 
 
        if (customerTier == null) { 
            return successResponse(); 
        } 
 
        /* 
         * Determine discount factor. 
         */ 
        Decimal discountFactor; 
 
        if (customerTier.equalsIgnoreCase('Gold')) { 
 
            discountFactor = 0.80; 
 
        } else if (customerTier.equalsIgnoreCase('Silver')) { 
 
            discountFactor = 0.90; 
 
        } else if (customerTier.equalsIgnoreCase('Bronze')) { 
 
            discountFactor = 0.95; 
 
        } else { 
 
            return successResponse(); 
        } 
 
        /* 
         * Get SalesTransactionItems. 
         */ 
        List<Object> items = 
            (List<Object>) queryResult.get( 
                'SalesTransactionItem' 
            ); 
 
        if (items == null || items.isEmpty()) { 
            return successResponse(); 
        } 
 
        /* 
         * Update every SalesTransactionItem. 
         */ 
        for (Object itemObject : items) { 
 
            Map<String, Object> item = 
                (Map<String, Object>) itemObject; 
 
            Map<String, Object> tagValue = 
                (Map<String, Object>) 
                    item.get('tagValue'); 
 
            if (tagValue == null) { 
                continue; 
            } 
 
            /* 
             * IMPORTANT:
             * Skip the QLI if it is currently being deleted.
             * This prevents:
             *
             * "Failed to update as data not in updatable state."
             */ 
            Object lineItemObject = 
                tagValue.get('LineItem'); 
 
            if (lineItemObject instanceof Map<String, Object>) { 
 
                Map<String, Object> lineItem = 
                    (Map<String, Object>) 
                        lineItemObject; 
 
                Object dmlStatus = 
                    lineItem.get('dmlStatus'); 
 
                if (dmlStatus != null && 
                    String.valueOf(dmlStatus) 
                        .equalsIgnoreCase('DELETED')) { 
 
                    continue; 
                } 
            } 
 
            /* 
             * Get current NetUnitPrice. 
             */ 
            Decimal currentNetUnitPrice = 
                getDecimalTagValue( 
                    tagValue, 
                    'NetUnitPrice' 
                ); 
 
            /* 
             * Get quantity. 
             */ 
            Decimal quantity = 
                getDecimalTagValue( 
                    tagValue, 
                    'LineItemQuantity' 
                ); 
 
            if (currentNetUnitPrice == null || 
                quantity == null || 
                quantity == 0) { 
 
                continue; 
            } 
 
            /* 
             * Apply Customer Tier discount. 
             * 
             * Gold   = 20% 
             * Silver = 10% 
             * Bronze = 5% 
             */ 
            Decimal newNetUnitPrice = 
                currentNetUnitPrice * 
                discountFactor; 
 
            Decimal newNetTotalPrice = 
                quantity * 
                newNetUnitPrice; 
 
            /* 
             * Get LineItem. 
             */ 
            String lineItem = 
                getTagValue( 
                    tagValue, 
                    'LineItem' 
                ); 
 
            if (lineItem == null) { 
                continue; 
            } 
 
            /* 
             * Get data path. 
             */ 
            List<Object> dataPath = 
                (List<Object>) 
                    item.get('dataPath'); 
 
            if (dataPath == null || 
                dataPath.isEmpty()) { 
 
                continue; 
            } 
 
            /* 
             * Follow the same pattern as 
             * the working reference hook. 
             */ 
            dataPath.remove(0); 
 
            /* 
             * Build update attributes. 
             */ 
            List<Map<String, Object>> attributes = 
                new List<Map<String, Object>>(); 
 
            attributes.add( 
                new Map<String, Object>{ 
                    'attributeName' => 
                        'NetUnitPrice', 
 
                    'attributeValue' => 
                        newNetUnitPrice 
                } 
            ); 
 
            attributes.add( 
                new Map<String, Object>{ 
                    'attributeName' => 
                        'NetTotalPrice', 
 
                    'attributeValue' => 
                        newNetTotalPrice 
                } 
            ); 
 
            /* 
             * Build update node. 
             */ 
            List<Object> nodePathAndAttributes = 
                new List<Object>(); 
 
            nodePathAndAttributes.add( 
                new Map<String, Object>{ 
                    'nodePath' => 
                        new Map<String, Object>{ 
                            'dataPath' => 
                                dataPath 
                        }, 
 
                    'attributes' => 
                        attributes 
                } 
            ); 
 
            /* 
             * Update pricing context. 
             */ 
            context.updateContextAttributes( 
                new Map<String, Object>{ 
                    'contextId' => 
                        contextId, 
 
                    'nodePathAndAttributes' => 
                        nodePathAndAttributes 
                } 
            ); 
        } 
 
        return successResponse(); 
    } 
 
 
    private static String getTagValue( 
        Map<String, Object> tagValue, 
        String tagName 
    ) { 
 
        if (!tagValue.containsKey(tagName)) { 
            return null; 
        } 
 
        Object tagObject = 
            tagValue.get(tagName); 
 
        if (!(tagObject instanceof Map<String, Object>)) { 
            return null; 
        } 
 
        Map<String, Object> tag = 
            (Map<String, Object>) tagObject; 
 
        if (!tag.containsKey('tagValue')) { 
            return null; 
        } 
 
        Object value = 
            tag.get('tagValue'); 
 
        if (value == null) { 
            return null; 
        } 
 
        return String.valueOf(value); 
    } 
 
 
    private static Decimal getDecimalTagValue( 
        Map<String, Object> tagValue, 
        String tagName 
    ) { 
 
        String value = 
            getTagValue( 
                tagValue, 
                tagName 
            ); 
 
        if (value == null) { 
            return null; 
        } 
 
        try { 
            return Decimal.valueOf(value); 
        } catch (Exception e) { 
            return null; 
        } 
    } 
 
 
    private static RevSignaling.TransactionResponse 
        successResponse() { 
 
        RevSignaling.TransactionResponse response = 
            new RevSignaling.TransactionResponse(); 
 
        response.status = 
            RevSignaling.TransactionStatus.SUCCESS; 
 
        return response; 
    } 
}