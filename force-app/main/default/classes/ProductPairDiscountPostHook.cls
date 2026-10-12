global class ProductPairDiscountPostHook
    implements RevSignaling.SignalingApexProcessor {

    private static final Decimal DISCOUNT_FACTOR = 0.90;

    private static final Set<String> ELIGIBLE_PRODUCTS =
        new Set<String>{
            'QE-NH',
            'NX-AI'
        };

    global RevSignaling.TransactionResponse execute(
        RevSignaling.TransactionRequest request
    ) {

        String contextId = request.ctxInstanceId;

        Context.IndustriesContext context =
            new Context.IndustriesContext();

        Map<String, Object> queryInput =
            new Map<String, Object>{
                'contextId' => contextId,
                'tags' => new List<String>{
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

        List<Object> items =
            (List<Object>) queryResult.get(
                'SalesTransactionItem'
            );

        if (items == null || items.isEmpty()) {
            return successResponse();
        }

        /*
         * Store the eligible products.
         */
        Map<String, Map<String, Object>> eligibleItems =
            new Map<String, Map<String, Object>>();

        Map<String, Decimal> itemTotalPrices =
            new Map<String, Decimal>();

        /*
         * Read QE-NH and NX-AI.
         */
        for (Object itemObject : items) {

            Map<String, Object> item =
                (Map<String, Object>) itemObject;

            Map<String, Object> tagValue =
                (Map<String, Object>) item.get(
                    'tagValue'
                );

            if (tagValue == null) {
                continue;
            }

            String productCode =
                getTagValue(
                    tagValue,
                    'ItemProductCode'
                );

            if (productCode == null ||
                !ELIGIBLE_PRODUCTS.contains(productCode)) {
                continue;
            }

            Decimal itemTotalPrice =
                getDecimalTagValue(
                    tagValue,
                    'ItemTotalPrice'
                );

            if (itemTotalPrice == null) {
                continue;
            }

            eligibleItems.put(
                productCode,
                item
            );

            itemTotalPrices.put(
                productCode,
                itemTotalPrice
            );
        }

        /*
         * Both products must exist.
         */
        if (!itemTotalPrices.containsKey('QE-NH') ||
            !itemTotalPrices.containsKey('NX-AI')) {

            return successResponse();
        }

        Decimal qeNhTotal =
            itemTotalPrices.get('QE-NH');

        Decimal nxAiTotal =
            itemTotalPrices.get('NX-AI');

        /*
         * If equal, no discount.
         */
        if (qeNhTotal == nxAiTotal) {
            return successResponse();
        }

        /*
         * Find the lower-priced product.
         */
        String lowerProductCode;

        if (qeNhTotal < nxAiTotal) {
            lowerProductCode = 'QE-NH';
        } else {
            lowerProductCode = 'NX-AI';
        }

        Map<String, Object> lowerPricedItem =
            eligibleItems.get(
                lowerProductCode
            );

        if (lowerPricedItem == null) {
            return successResponse();
        }

        Map<String, Object> lowerTagValue =
            (Map<String, Object>)
                lowerPricedItem.get(
                    'tagValue'
                );

        if (lowerTagValue == null) {
            return successResponse();
        }

        /*
         * Get current NetUnitPrice.
         */
        Decimal currentNetUnitPrice =
            getDecimalTagValue(
                lowerTagValue,
                'NetUnitPrice'
            );

        /*
         * Get quantity.
         */
        Decimal quantity =
            getDecimalTagValue(
                lowerTagValue,
                'LineItemQuantity'
            );

        if (currentNetUnitPrice == null ||
            quantity == null ||
            quantity == 0) {

            return successResponse();
        }

        /*
         * Apply hardcoded 10% discount
         * to the lower-priced product.
         */
        Decimal newNetUnitPrice =
            currentNetUnitPrice * DISCOUNT_FACTOR;

        Decimal newNetTotalPrice =
            quantity * newNetUnitPrice;

        /*
         * Get LineItem.
         */
        String lineItem =
            getTagValue(
                lowerTagValue,
                'LineItem'
            );

        if (lineItem == null) {
            return successResponse();
        }

        /*
         * Get data path.
         */
        List<Object> dataPath =
            (List<Object>)
                lowerPricedItem.get(
                    'dataPath'
                );

        if (dataPath == null ||
            dataPath.isEmpty()) {

            return successResponse();
        }

        /*
         * Follow the same pattern as the
         * working reference code.
         */
        dataPath.remove(0);

        /*
         * Build update for:
         *
         * NetUnitPrice
         * NetTotalPrice
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