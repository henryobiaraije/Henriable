# **Henriable Vehicles**

**Initial Draft** [https\://docs.google.com/document/d/1d535kqXI0As0L6\_tm720\_T\_nT1fOusoatpLwmwGB43g/edit?usp=sharing](https://docs.google.com/document/d/1d535kqXI0As0L6_tm720_T_nT1fOusoatpLwmwGB43g/edit?usp=sharing) 

# **Summary**

1.  Vehicle investment platform where investors invest, riders hire (via hire purchase) and paying periodically.  
2. Yields are shared to investors and admin.

# **Requirements**

1. Currency is in USDC  
2. Before launch, calculate to ensure the amount riders will pay would be able to pay out the percentages to investors, at least if the rider did not default even once.

# **Specifics**

## **Admin powers**

1. Launch contract with settings that include  
   1. Assets to invest in and their own setting too. E.g.  
      1. Keke: (e.g. \$10,000 cost price) With settings like  
         1. Senior Investors  
            1. Percentage investment of initial cost of asset (e.g. \$1000)  
            2. Percentage reward of invested amount.  
         2. Junior investors  
            1. Percentage investment of initial cost of assets  
            2. Percentage reward of invested amount.  
         3. Percentage riders would pay per time\_frame. (This should meet the rewards of the investments)  
         4. Perc   
      2. Car, Bike, Truck, e.t.c  
2. Set at any time how many new assets they can afford to accept investment for. E.g:  
   1. From the 10th of next month to the 20th, we would accept investment of 20 Assets (Keke)  
   2. This allows them to accept the number of investments they can manage.  
   3. During that time, people can join by investing.  
3. Update settings, like costs, percentage yields, e.t., of existing assets for new rounds of investments.  
4. Set a time frame for a certain number of drivers or riders to register to take up the already minted assets at a higher purchase price by paying the initial fee.  
5. Approve riders and refund unapproved riders.  
6. If a rider defaults, admin can apply some penalties like  
   1. Remove the rider and recover the asset.  
7. 

## **Crowd Investment**

1. This is how investors invest in the business.  
2. An investor can invest any amount towards a target goal, which includes:  
   1. Bike  
   2. Keke  
   3. Car  
   4. Truck	  
3. Each would have a minimum investment amount set during launch  
4. Investment is in 2 tiers  
   1. Senior pool (lower risk/ low reward)  
      1. These are paid first during every payout time  
   2. Junior pool (higher risk/ high reward)  
      1. Then the rest of these share the remaining reward according to yield settings.  
5.  

## **Riders** 

1. Riders are able to register during the rider registration window and pay, then wait to for further instructions and to be approved.  
2. Riders are also able to set their USDC wallet for automatic deposits.  
3. Riders can pay in their periodic payment at the right time.  
4. If a rider defaults, the admin would issue a penalty.  
5. 

# **Future Improvements**

1. Find a way to mix senior and junior investors enough that theres enough junior investors to absorb potential (and average anticipated lost) too.  
2. Maybe in the future have stakers just like in blockchain that just stake to make profit but not invest but could get their stake slashed to absorb losses.  
3. Add feature in web2 to calculate in real time as admin make settings in preparation to launch the contract to specifically show details of things like  
   1. How much defaulters and at what point the minimum junior investors to mix in every investment could guarantee.  
4. Add minimum and maximum settings for both tier of investors instead of just one fixed investment amount(percent).  
5. Add a feature to auction off recovered assets and share proceeds, or even higher them out to new riders at a discount. And also apportion risk absorption.  
6. Add more penalty options to defaulted riders, e.g.  
   1. Slash their savings and give them another chance.  
7. Add a feature to bring mechanics into the fold so that, if there are any fixes, they do it and charge appropriately in a transparent way.  
8. Add a feature to 

# **Initial Code Draft**

1. ## **Structs**

   1. ### HAsset

      1. Id: (bytes32) (Unique)  
      2. active: (bool) (Can only be updated if no investor has invested in any investment with this asset)  
      3. name: (bytes32)  
      4. cost\_price (uint256)  
      5. sell\_price (uint256): Total amount rider would pay over time. (Must cover investors’ rewards.  
      6. senior\_investor\_buying\_price: (uint256) (total investment from senior investors)  
      7. senior\_investor\_profit: (uint256) (total profit the investor would make over time.)  
      8. junior\_investor\_buying\_price: (uint256) (total investment from senior investors)  
      9. junior\_investor\_profit: (uint256) (total profit the investor would make over time.)  
      10. total\_number\_of\_senior\_investors\_needed: (uint256) (The total number of senior investors needed)  
      11. total\_number\_of\_junior\_investors\_needed: (uint256) (The total number of junior investors needed)  
   2. ### HInvestment {#hinvestment}

      1. Single struct. Solidity structs cannot inherit (no TypeScript-style `extends`), so the  
         admin-supplied settings and the contract-filled fields are combined here. In code  
         they are grouped with editor-folds: "Fields: Admin Supplied" and "Fields: Contract Filled".  

      2. #### Fields: Admin Supplied

         1. investmentId: (bytes32) (unique investment slot ID)  
         2. assetId: (bytes32) (The asset ID to invest in)  
         3. totalSeniorInvestorsNeeded: (uint256)  
         4. totalJuniorInvestorsNeeded: (uint256)  
         5. riderInitialBuyinUsd: (uint256)  
         6. periodicRiderPayingInMinutes: (uint256)  
         7. minimumRiderPeriodicPayingsUsd: (uint256)  

      3. #### Fields: Contract Filled

         1. active: (bool) (forced true on creation; can only be updated while no investor has invested in it)  
         2. seniorInvestorsList: Array of investor addresses  
         3. seniorInvestors: mapping(investorAddress => investorIndex)  
         4. juniorInvestorsList: Array of investor addresses  
         5. juniorInvestors: mapping(investorAddress => investorIndex)  
         6. investmentsDoneAt: uint256  
         7. status: (HInvestmentStatus)  
         8. timeNextInvestmentStart: (uint256) (Time the next investment round is allowed to start)  
         9. timeNextInvestmentEnd: (uint256) (Time the next investment round would end)  
         10. timeNextRiderHireRequestStart: (uint256) (Time the next hire purchase request round is scheduled to start)  
         11. timeNextRiderHireRequestEnd: (uint256) (Time the next hire purchase request round is scheduled to end)  
         12. ridersHirePurchaseRequestsList: Array of (uint256): points to the specific rider hire-purchase request.  
         13. ridersHirePurchaseRequests: mapping(riderAddress => uint256) (the index of the hire-purchase request)  
         14. riderWhoHiredIt: address (the address of the rider who will/or hired it)  
         15. riderNextPayinDate: uint256  
         16. riderPayinsHistory: (HPayingHistory)  
         17. riderSavings: HRiderSavingsHistory  
         18. investorPayoutHistory: mapping(investorAddress => HInvestorPayoutsHistory)  
         19. investmentPayoutHistory: (HInvestmentPayoutsHistory)  
         20. contractPayoutHistory: (HOwnerPayoutsHistory)  
         21. nftTokenId: (Token id of the newly minted NFT title for the asset being invested in here)  
         22. timeRiderCompletedPayments: (uint256)  
         23. timeNftTransferedToRider: (uint256)  

   4. ### HInvestor

      1. address: (address)  
      2. name: (bytes32)  
      3. country: (bytes32)  
      4. age: (bytes32) (must be at least 18 years)

   5. ### HRider

      1. address: (address)  
      2. name: (bytes32)  
      3. country: (bytes32)  
      4. age: (bytes32) (must be at least 18 years)

   6. ### HRiderHigherPurchaseRequest

      1. investmentId: (bytes32)  
      2. timeRequested: (uint256)

   7. ### HRiderPayin

      1. riderId: (bytes32)  
      2. investmentId: (bytes32)  
      3. amountPaid: (uint256)  
      4. timePaid: (uint256)  
      5. addressPaidInto: (address) (this)

   8. ### HPayingHistory

      1. riderAddress: (address)  
      2. totalAmountPaid: uint256  
      3. totalNumberOfTimesPaid: uint256  
      4. targetTotalPay: (uint256)

   9. ### HOwnerPayout

      1. investmentId: (bytes32)  
      2. amountPaid: (uint256)  
      3. timePaid: (uint256)  
      4. addressPaidInto: (ownerUsdToken)

   10. ### HOwnerPayoutsHistory

       1. totalAmountPaid: uint256  
       2. totalNumberOfTimesPaid: uint256

   11. ### HInvestorPayout

       1. investmentId: (bytes32)  
       2. amountPaid: (uint256)  
       3. timePaid: (uint256)  
       4. addressPaidInto: (address)

   12. ### HInvestorPayoutsHistory

       1. investorAddress: address  
       2. investmentId: (bytes32)  
       3. totalAmountPaid: uint256  
       4. totalNumberOfTimesPaid: uint256  
       5. targetTotalPay: (uint256)

   13. ### HInvestmentPayoutsHistory

       1. investmentId: (bytes32)  
       2. totalAmountPaid: uint256  
       3. totalNumberOfTimesPaid: uint256  
       4. targetTotalPay: (uint256)  
   14. HRiderSavingsHistory  
       1. Represents  
          1. Rider savings that can be slashed.   
          2. Part of every rider periodic payings is saved here to refund them later if they remained committed at the end of the their hire purchase.   
          3. It servers as additional income for them to use for repairs and cash since they now own the vehicle and to be slashed from if they default or paid late.  
       2. Properties  
          1. riderAddress: (address)  
          2. totalAmountSaved: (uint256)  
          3. savings: array HRiderSavings  
   15. HRiderSavings  
       1. Represents  
          1. One saving made by a rider.  
       2. Properties  
          1. riderAddress: (address)  
          2. amountSaved: (uint256)  
          3. timeSaved: (uint256)

   16. ### 

2. ## **Enums**

   1. ### HInvestmentType

      1. Variations  
         1. Senior  
            1. Represents a senior investor  
         2. Junior  
            1. Junior investor

   2. ### HInvestmentStatus

      1. Variations  
         1. Pending  
            1. Investment added but investing has not begun.  
         2. AcceptingInvestments  
            1. Investors can currently invest.  
         3. InvestmentDone  
            1. We have all the investors we need.  
         4. AcceptingRiders  
            1. Riders can now apply by sending request to hire the asset in the investment.  
         5. Hired  
            1. A rider has been hired and is now making periodic payments.  
         6. Complete  
            1. Rider done with payment and NFT title transferred to them.  
         7.   
   3. 

3. ## **States**

   1. ### Default

      1. #### assets: 

         1. address(assetId(bytes32), HAsset)	  
         2. ownerUsdToken

      2. #### assetInvestments 

         1. mapping(assetId \=\> Array of investmentIds  uint256)

      3. #### investmentsList 

         1. Array of [HInvestment](#hinvestment) 

      4. #### investments 

         1. mapping(investmentId \=\> uint256) (stored as index + 1; 0 means "not registered")

      5. #### investorsList 

         1. Array of HInvestor 

      6. #### investors 

         1. mapping(investorAddress \=\>  uint256)

      7. #### ridersList 

         1. Array of HRider 

      8. #### riders 

         1. mapping(riderAddress \=\>  uint256)

      9. #### ridersHirePurchasesRequestsList 

         1. Array of HRiderHigherPurchaseRequest

      10. #### ridersHireRequestPurchasesByInvestment  {#ridershirerequestpurchasesbyinvestment}

          1. mapping(riderId \=\> mapping( investmentId \=\>   uint256))  
             1. uint256 is the index of the investment.

      11. #### rejectedRiders  {#rejectedriders}

          1. mapping(riderId \=\> mapping( investmentId \=\>   uint256))  
          2.  

      12. #### riderPayinsList 

          1. Array of (HRiderPayin)   
          2. 

      13. #### riderPayins 

          1. mapping(riderAddress \=\> mapping( investmentId \=\>   uint256)) (uint256 \= riderPayinsList index)  
          2.  

      14. #### investorPayoutList

          1. Array of (HInvestorPayout)   
          2. 

      15. #### investorPayouts

          1. mapping(investorAddress \=\> mapping( investmentId \=\>   uint256)) (uint256 \= investorPayoutList index)  
          2.  

      16. #### ownerPayoutsList

          1. Array of (HOwnerPayout)   
          2. 

      17. #### ownerPayouts

          1. mapping(investmentId \=\>   uint256)) (uint256 \= ownerPayoutsListindex)  
          2.  

      18. #### ownerPayoutHistory

          1. mapping(investmentId \=\>   uint256)) (uint256 \= ownerPayoutsListindex)  
          2.  

      19. #### completedRiderInvestmentList

          1. Array of (uint256) (uint256 \= index of investmentsList )  
          2.   
      20.   
      21. 

   2. ### Rider Hire-Purchase Payment Complete

      1. #### investmentsCompleted: 

         1. Array of uint256: (Points to each investment by index.) (Can never be cleared as it showed investments that a rider has completed paying for). (Similar to others below.)  
   3. 

4. ## **Functions**

   1. ###  **constructor()**

      1. Parameters  
         1. \_ownerUsdToken  
         2.   
      2. Features  
         1.   
   2. Externals

      1. ### Admin Add Assets & Investments

         1. #### actionAdminAddAsset()

            1. Function  
               1. Allow the admin to add assets that can be invested in.  
            2. Param  
               1. \_asset:  HAsset  
            3. Features  
               1. Add Asset  
               2. Update States   
                  1. assets  
                  2.   
               3.   
            4. 

         2. #### actionAdminChangeAssetStatus()

            1. Function  
               1. Allow admin to change the status of an asset.  
            2. Param  
               1. \_assetID: bytes32  
               2. \_status:  bool  
            3. Features  
               1. Also disable investor status if false too.  
               2. Update States 

                  1. ### assets

                  2.   
               3. 

         3. #### actionAdminAddInvestment()

            1. Function  
               1. Allow the admin to add investments that can be invested in.  
            2. Param  
               1. \_investmentId: (bytes32) (must be unique and non-zero)
               2. \_assetId: (bytes32) (must reference a registered, active asset)
               3. \_totalSeniorInvestorsNeeded: (uint256) (must be non-zero)
               4. \_totalJuniorInvestorsNeeded: (uint256) (must be non-zero)
               5. \_riderInitialBuyinUsd: (uint256) (must be non-zero)
               6. \_periodicRiderPayingInMinutes: (uint256) (must be non-zero)
               7. \_minimumRiderPeriodicPayingsUsd: (uint256) (must be non-zero)
               8. Note: {HInvestment} contains mappings, so it cannot be passed as a calldata
                  parameter; the admin-supplied settings are passed as individual arguments.
            3. Features  
               1. Verify all param values  
               2. Verify and calculate that param values and asset settings match to ensure payments to investors. Use calcInvestmentOpportunityLevel1SettingsAccuracy()   
               3. Update States   
                  1. investmentsList   
                  2. investments   
                  3. assetInvestments   
               4.   
            4. 

         4. #### actionAdminChangeInvestmentStatus()

            1. Function  
               1. Allow the admin to add assets that can be invested in.  
            2. Param  
               1. \_investmentID: bytes32  
               2. \_status:  bool  
            3. Features  
               1. Ensure no investment that has an investor  has this asset in it.  
               2. Update States   
                  1. assets  
                  2.   
         5. 

      2. ### Admin Add Investment Opportunities

         1. #### actionAdminSetNextInvestmentTimes()

            1. Function  
               1. Allows the admin to set or update the next start and end time for the next round of investments  
            2. Params  
               1. \_investmentID:   
               2. startTime: (uint256) (start timestamp) (must be in the future)  
               3. endTime: (uint256) (end timestamp) (must be after startTime)  
            3. Features  
               1. Ensure investment status is (HInvestmentStatus.Pending)  
               2. Ensure there are assets to invest in and enabled  
               3.   
               4. Ensure endTime is greater than startTime  
               5. Update states  
                  1. HInvestment.timeNextInvestmentStart  
                  2. HInvestment.timeNextInvestmentEnd   
               6. 

         2. #### actionAdminClearNextInvestmentsTimes() 

            1. Function  
               1. Reset next investment start and stop times to 0  
            2. Params  
               1. \_investmentID

      3. ### **Investors Investing**

         1. #### actionInvest() 

            1. Function  
               1. Allows investors to invest in assets.  
            2. Parameters  
               1. \_investor: HInvestor    
               2. \_investmentType: HInvestmentType  
               3. \_ investmentId:  
               4. \_approvedUSDAmount: (uint256)  
            3. Features  
               1. Call maybeUpdateInvestmentStatus()    
               2. Ensure investment is ongoing   
               3. Create or update investor(by investor address)  
               4.   
               5. Ensure there is still an open slot to invest in  
               6. Ensure the approved amount is correct for the asset.  
               7. Update states  
                  1. Update (investorsList ) and (investors)  
                  2.   
                  3. Update (HInvestment.seniorInvestorsList) and (HInvestment.seniorInvestors) or (HInvestment.juniorInvestorsList) and (HInvestment.juniorInvestors)  
                  4. Maybe mint a new custom NFT as title of the new investment.  
                     1. Done when all the needed investment comes in but still belongs to the contract until the acceptance rider completes payment.  
                  5. Maybe update status to (HInvestmentStatus.InvestmentDone)  
                  6. Maybe update (HInvestment.investmentsDoneAt)  
                  7.   
               8. 

      4. ### **Admin sets rider hiring time**

         1. #### actionSetNextHireRoundTime()

            1. Function  
               1. Used by admin to clear any next time frame riders can hire vehicles by hire-purchase  
            2. Params  
               1. \_startTime: (uint256) (start timestamp) (must be in the future)  
               2. \_endTime: (uint256) (end timestamp) (must be after startTime)  
            3. Features  
               1. Ensure there are investments to hire  
               2. Ensure that investing is not ongoing.  
               3. Ensure endTime is greater than startTime  
               4. Update states  
                  1. HInvestment.timeNextRiderHireRequestStart  
                  2. HInvestment.timeNextRiderHireRequestEnd

         2. #### actionClearNextHireTime()

            1. Function  
               1. Used by admin to clear any next investment round by clearing the times and setting them to 0\.  
            2. Parameters  
               1. \_investmentID: 

   3. ### Riders Register To Hire

      1. #### actionRiderRegisterAsARider()

         1. Function  
            1. Allow riders to register and pay to start hire-purchase of an asset.  
         2. Parameters  
            1. name: (bytes32)  
            2. country: (bytes32)  
            3. age: (bytes32) (must be at least 18 years)  
            4. approvedInitialBuyin: (USDC) (Amount required and pre approved by user in their wallet and to be deducted)  
            5. investmentId: The asset ID.  
         3. Features  
            1. Call maybeUpdateInvestmentStatus()    
            2. Ensure approvedInitialBuyin is \>= HInvestment.riderInitalBuyinUsd  
            3. Ensure registration is in progress for the investment.  
            4. Ensure rider has not registered for current round (use ridersHireRequestPurchasesByInvestment )  
            5. Ensure the right USD for investmentType was sent  
            6. Ensure rider is 18 years or older  
            7. Ensure other params are valid  
            8. Create ride hire request entry  
            9. Transfer rider collateral USD to owner usd token  
            10. Update States  
                1.   ridersList   
                2. riders   
                3. ridersHirePurchasesRequestsList   
                4. ridersHireRequestPurchasesByInvestment   
                5. HInvestor.ridersHirePurchaseRequestsList  
                6. HInvestor.ridersHirePurchaseRequests  
                7. 

      2. #### actionRiderSetMyPayoutUSDCAddress()

         1. Function:  
            1. Allows an investor and rider to set the USDC address their payouts would be made to.  
         2. Parameters.  
            1. \_payoutAddress  
         3. Features  
            1. Ensure rider exists  
            2. …  
            3. Update States  
               1. ridersList   
            4.   
      3.  

   4. ### Admin Accept/Reject Riders

      1. #### actionAdminAcceptRider()

         1. Function:  
            1. Accept one rider out of all riders that applied for hire-purchase on an investment while rejecting others.  
         2. Parameters.  
            1. \_investmentId:  
            2. \_riderAddress:  
         3. Features  
            1. …  
            2. Investment exists  
            3. Ensure rider exists  
            4. Ensure rider sent a request (from ridersHirePurchasesRequestsList )  
            5. Ensure riders were not rejected for this investment before.  
            6. Update states  
               1. HInvestment.riderWhoHiredIt  
               2. investmentsList  (use [ridersHireRequestPurchasesByInvestment](#ridershirerequestpurchasesbyinvestment) ) to get the investment index. Then update (riderWhoHiredIt in HInvestment)  
               3. For other riders who applied  
                  1. update ([rejectedRiders](#rejectedriders) )  
                  2. Refund their USD   
               4. Update HInvestment.riderNextPayinDate in investmentsList  (ensure its at least more time than now \+ HInvestment.periodicRiderPayingInImutes)  
               5.   
            7. …

      2. ### Rider Payings

         1. #### actionRiderPayin()

            1. Function:  
               1. Allow riders who have a hire-purchase currently running to pay in their periodic payings  
            2. Parameters.  
               1. \_investmentID:  
               2. \_approvedUSD:  
            3. Features  
               1. …  
               2. Investment exists  
               3. Ensure rider exists  
               4. Ensure rider was accepted  
               5. Ensure has not completed payment.  
               6. Revert if the rider is paying late.  
               7. Ensure minimum amount needed was approved (HInvestment.minimumRiderPeriodicPayingsUsd)  
               8.   
               9. Update states  
                  1. Update (riderPayinsList ) and (riderPayins )   
                  2. HInvestment.riderPayinsHistory  in investmentsList    
                  3. Update (HInvestment.riderNextPayinDate) (calculate and add investment periodic payin minutes)  
                  4. After sharing calculation:  
                  5. Update   
                     1. (investorPayoutList ) and   
                     2. (investorPayouts) and  
                     3. (HInvestment.investorPayoutHistory) and  
                     4. (HInvestment.investmentPayoutHistory) and   
                     5. (ownerPayoutsList)  
                     6. (ownerPayouts)  
                     7. (ownerPayoutHistory)  
                     8. Maybe update (HInvestment.timeRiderCompletedPayments)  
                     9. Maybe call (actionTransferOwnershipToRider())  
               10. Charge the rider  
               11. Share the yield. Use calc… to calculate sharing formula.  
               12.   
               13. …

      3. ### Rider  Completes Payment

         1. #### actionTransferOwnershipToRider()

            1. Function:  
               1. Allow riders who have a hire-purchase currently running to pay in their periodic payings  
            2. Parameters.  
               1. \_riderAddress:  
               2. \_investmentID:  
            3. Features  
               1. …  
               2. Payable to desensitize random calls.  
               3. Investment exists  
               4. Ensure rider exists  
               5. Ensure rider was accepted  
               6. Ensure has completed payment.  
               7.   
               8. Update states  
                  1. Update (investmentsCompleted  )  
                  2. HInvestment.timeNftTransferedToRider  in investmentsList    
                  3.   
               9.   
               10. …

   5. ### Maybe

      1. #### maybeUpdateInvestmentStatus()

         1. Function  
            1. To update investment status when necessary.  
         2. Parameters  
            1. \_investmentId: The investment id.  
         3. Features  
            1.  Update to HInvestmentStatus.AcceptingInvestments  
               1. When investment is in Pending but now its in window of set investment time.  
            2.  … others too  
            3.    
            4. 

   6. ### 

   7. ### Calculators

      1. #### isInvestmentStatus()

         1. Function  
            1. Return true if the investment is in this status.  
         2. Parameters  
            1. \_investmentId: The investment id.  
            2. \_status: HInvestmentStatus  
         3. Features  
            1.   
            2. 

   8. ### Calculators

      1. #### calcSharingFomular()

         1. Function  
            1. When the rider has paid their hire purchase payings completely, the asset should automatically be transferred to them.  
         2. Parameters  
            1. \_investmentId: The investment id.  
         3. Features  
            1.  Ensure investment id is correct  
            2. Ensure payings are complete  
            3. Update States  
               1.    
            4. Transfer NFT title to rider  
            5. 

      2. #### calcAssetSettingsAccuracy()

         1. Function  
            1. This would calculate for an asset to see if all property settings calculations are accurate. E.g.  
               1. If the selling price would be enough to pay for investors’ profits  
         2. Parameters  
            1.   
         3. Features  
            1.    
      3. calcInvestmentOpportunityLevel1SettingsAccuracy()  
         1. Function  
            1. This would calculate to ensure setting submitted by the admin to create an investment would work to ensure accurate payouts.  
            2. Placeholder: currently a stub that always returns true.  
         2. Parameters  
            1. HInvestment (the staged investment to validate)  
         3. Features  
            1.  

# **Future Improvements**

1. When a rider defaults, add ways to penalize them. E.g.  
   1. Slash their savings  
   2. Remove them  
2. 