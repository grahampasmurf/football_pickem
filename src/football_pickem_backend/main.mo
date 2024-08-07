import Result "mo:base/Result";
import Time "mo:base/Time";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import TrieMap "mo:base/TrieMap";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";
import Nat64 "mo:base/Nat64";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import Text "mo:base/Text";

// how to run
// # Starts the replica, running in the background
// dfx start --background

// # Deploys your canisters to the replica and generates your candid interface
// dfx deploy
// Once the job completes, your application will be available at `http://localhost:4943?canisterId={asset_canister_id}`.

// If you have made changes to your backend canister, you can generate a new candid interface with

// ```bash
// npm run generate
// ```

// at any time. This is recommended before starting the frontend development server, and will be run automatically any time you run `dfx deploy`.

// If you are making frontend changes, you can start a development server with

// ```bash
// npm start
// ```

actor {
  // public query func greet(name : Text) : async Text {
  //   return "Hello, " # name # "!";
  // };
  type Result<A, B> = Result.Result<A, B>;

    type Role = {
        #player;
        #commish;
    };

    type Member = {
        name : Text;
        role : Role;
    };

    type ListingStatus = {
        #Active;
        #Inactive;
        #Sold;
    };

    type PropertyId = Nat;
    type ListedProperty = {
        id : Nat;
        mls : Nat;
        address : Text;
        Features : Text;
        // Picture : Blob; // Picture of the property
        // Map : Blob; // Map of the propaerty
        // linkToListing : Text;
        creator : Principal; // The member who created the listing
        created : Time.Time; // The time the listing was created
        status : ListingStatus; // The current status of the listing
        highestBid : Nat;
        highestBidder : ?Principal; // allow null
    };

    type HashMap<A, B> = HashMap.HashMap<A, B>;

    var nextPropertyId : Nat = 0;
    let properties = TrieMap.TrieMap<PropertyId, ListedProperty>(Nat.equal, Hash.hash);
    let fpdao : HashMap<Principal, Member> = HashMap.HashMap<Principal, Member>(0, Principal.equal, Principal.hash);
    // fpdao = Football Pickem DAO

    public query func greet(name : Text) : async Text {
        return "Hello! Welcome to the Football Picking DAO, " # name # "!";
    };

    // Register a new member in the fpdao with the given name and principal of the caller
    // New members are always player
    // the very first member becomes an commish (slang for Commissioner), and can then promote others to commishes
    // Returns an error if the member already exists
    public shared ({ caller }) func registerMember(name : Text) : async Result<(), Text> {
        switch (fpdao.get(caller)) {
            case (?member) return #err("Member already exists");
            case (null) {
                if (fpdao.size() == 0) {
                    // if the fpdao is size 0 (no members) then this first member will be an commish
                    fpdao.put(
                        caller,
                        {
                            name = name;
                            role = #commish;
                        },
                    );
                    return #ok();
                };
                // else add as a player
                fpdao.put(
                    caller,
                    {
                        name = name;
                        role = #player;
                    },
                );
                return #ok();
            };
        };
    };

    // Get the member with the given principal
    // Returns an error if the member does not exist
    public query func getMember(p : Principal) : async Result<Member, Text> {
        switch (fpdao.get(p)) {
            case (null) return #err("No member found");
            case (?member) return #ok(member);
        };
    };

    // "Promote" the player with the given principal into an commish
    // Returns an error if the player does not exist or is not a player
    // Returns an error if the caller is not an commish
    // Only an commish can call this function to promote a player to an commish
    // UPDATEME - change to makeAncommish
    public shared ({ caller }) func becomecommish(player : Principal) : async Result<(), Text> {
        switch (fpdao.get(caller)) {
            case (?member1) {
                switch (member1.role) {
                    case (#commish) {
                        switch (fpdao.get(player)) {
                            case (null) return #err("No member found");
                            case (?member2) {
                                switch (member2.role) {
                                    case (#player) {
                                        let newMember = {
                                            name = member2.name;
                                            role = #commish;
                                        };
                                        fpdao.put(player, newMember);
                                        return #ok();
                                    };
                                    case (#commish) return #err("Already a commish");
                                };
                                return #err("You are not a player");
                            };
                        };
                    };
                    case (#player) return #err("You are a player; only commishs may do this");
                };
            };
            case (null) return #err("You are not a member");
        };
    };

    func _isMember(p : Principal) : Bool {
        // check if p is member
        switch (fpdao.get(p)) {
            case (null) return false;
            case (?member) return true;
        };
    };

    func _iscommish(p : Principal) : Bool {
        // check if p is member
        switch (fpdao.get(p)) {
            case (null) return false;
            case (?member) {
                switch (member.role) {
                    case (#commish) {
                        return true;
                    };
                    case (#player) {
                        return false;
                    };
                };
                return false;
            };
        };
    };

    // create and get properties
    // Create a new listing and returns its id
    // Returns an error if the caller is not an commish
    // UPDATEME
    public shared ({ caller }) func createProperty(address : Text, MLS : Nat) : async Result<PropertyId, Text> {
        // check if caller is member
        if (not _isMember(caller)) {
            return #err("Not a member");
        };

        // only commishs can list a property
        if (not _iscommish(caller)) return #err("Only commishs can create a Property Listing.");

        let idSaved = nextPropertyId;
        let newProperty : ListedProperty = {
            id = idSaved;
            creator = caller;
            mls = MLS;
            Features = "";
            address = address;
            created = Time.now();
            highestBid = 0;
            highestBidder = null;
            status = #Active;
        };
        properties.put(idSaved, newProperty);

        nextPropertyId += 1;
        return #ok(idSaved);
    };

    // Bid for the given property
    // Returns an error if the property does not exist or the bid is not the highest bid
    public shared ({ caller }) func bidOnProperty(propertyId : PropertyId, bid : Nat) : async Result<(), Text> {
        if (not _isMember(caller)) {
            return #err("Not a member; cannot bid");
        };
        switch (properties.get(propertyId)) {
            case (null) return #err("Property not found");
            case (?property) {
                if (property.status == #Inactive or property.status == #Sold) return #err("Property is not available.");
                // check if already highest bidder
                if (property.highestBidder == ?caller) {
                    return #err("Already highest bidder.");
                };
                // passed all checks
                if (property.highestBid >= bid) {
                    let bidText = Nat.toText(bid);
                    let highestBidText = Nat.toText(property.highestBid);
                    return #err("Your bid of " # bidText # " did not exceed the highest bid of " # highestBidText # "!");
                };
                // bid is high enough
                let newProperty : ListedProperty = {
                    id = propertyId;
                    creator = property.creator;
                    mls = property.mls;
                    Features = "";
                    address = property.address;
                    created = property.created;
                    highestBid = bid;
                    highestBidder = ?caller;
                    status = #Active;
                };
                properties.put(property.id, newProperty);
                return #ok();
            };
        };
    };

    public shared ({ caller }) func acceptHighestBidOnProperty(propertyId : PropertyId) : async Result<(), Text> {
        // check if caller is member
        if (not _isMember(caller)) {
            return #err("Not a member");
        };

        // only commishs can list a property
        if (not _iscommish(caller)) return #err("Only commishs can accept a bid.");

        switch (properties.get(propertyId)) {
            case (null) return #err("Property not found");
            case (?property) {
                let newProperty : ListedProperty = {
                    id = propertyId;
                    mls = property.mls;
                    Features = "";
                    address = property.address;
                    created = property.created;
                    creator = property.creator;
                    highestBid = property.highestBid;
                    highestBidder = property.highestBidder;
                    status = #Sold;
                };
                properties.put(propertyId, newProperty);

                return #ok();
            };
        };
    };

    public shared ({ caller }) func deactivatePropertyListing(propertyId : PropertyId) : async Result<(), Text> {
        // check if caller is member
        if (not _isMember(caller)) {
            return #err("Not a member");
        };

        // only commishs can deactivate a property
        if (not _iscommish(caller)) return #err("Only commishs can deactivate a property.");

        switch (properties.get(propertyId)) {
            case (null) return #err("Property not found");
            case (?property) {
                let newProperty : ListedProperty = {
                    id = propertyId;
                    mls = property.mls;
                    Features = "";
                    address = property.address;
                    created = property.created;
                    creator = property.creator;
                    highestBid = property.highestBid;
                    highestBidder = property.highestBidder;
                    status = #Inactive;
                };
                properties.put(propertyId, newProperty);

                return #ok();
            };
        };
    };

    // Returns all the properties
    public query func getAllProperties() : async [ListedProperty] {
        return Iter.toArray(properties.vals());
    };

    // Returns all the members
    public query func getAllDAOMembers() : async [Member] {
        return Iter.toArray(fpdao.vals());
    };

    public shared query ({ caller }) func getMyself() : async Principal {
        return caller;
    };


// add the HTTPS outcalls functions
// source: https://github.com/dfinity/examples/blob/master/motoko/send_http_get/src/send_http_get_backend/Types.mo
// maybe later put them in their own canister, own Types.mo file

    public type HttpRequestArgs = {
        url : Text;
        max_response_bytes : ?Nat64;
        headers : [HttpHeader];
        body : ?[Nat8];
        method : HttpMethod;
        transform : ?TransformRawResponseFunction;
    };

    public type HttpHeader = {
        name : Text;
        value : Text;
    };

    public type HttpMethod = {
        #get;
        #post;
        #head;
    };

    public type HttpResponsePayload = {
        status : Nat;
        headers : [HttpHeader];
        body : [Nat8];
    };

    public type TransformRawResponseFunction = {
        function : shared query TransformArgs -> async HttpResponsePayload;
        context : Blob;
    };

    public type TransformArgs = {
        response : HttpResponsePayload;
        context : Blob;
    };

    public type CanisterHttpResponsePayload = {
        status : Nat;
        headers : [HttpHeader];
        body : [Nat8];
    };

    public type TransformContext = {
        function : shared query TransformArgs -> async HttpResponsePayload;
        context : Blob;
    };

    //3. Declaring the IC management canister which we use to make the HTTPS outcall
    public type IC = actor {
        http_request : HttpRequestArgs -> async HttpResponsePayload;
    };

     //function to transform the response
     // removed "Types." prefix, but put back in if we create separate Types.mo file
    public query func transform(raw : TransformArgs) : async CanisterHttpResponsePayload {
      let transformed : CanisterHttpResponsePayload = {
          status = raw.response.status;
          body = raw.response.body;
          headers = [
              {
                  name = "Content-Security-Policy";
                  value = "default-src 'self'";
              },
              { name = "Referrer-Policy"; value = "strict-origin" },
              { name = "Permissions-Policy"; value = "geolocation=(self)" },
              {
                  name = "Strict-Transport-Security";
                  value = "max-age=63072000";
              },
              { name = "X-Frame-Options"; value = "DENY" },
              { name = "X-Content-Type-Options"; value = "nosniff" },
          ];
      };
      transformed;
  };

  public func get_season_schedule_basic() : async Text {

    //1. DECLARE IC MANAGEMENT CANISTER
    //We need this so we can use it to make the HTTP request
    let ic : IC = actor ("aaaaa-aa");

    //2. SETUP ARGUMENTS FOR HTTP GET request

    // 2.1 Setup the URL and its query parameters
    let host : Text = "api.sportsdata.io/v3/nfl/scores/json";
    let apiEndpoint : Text = "SchedulesBasic";
    let season : Text = "2024";
    let key : Text = "";
    let url = "https://" # host # "/" # apiEndpoint # "/" # season;

    // 2.2 prepare headers for the system http_request call
    let request_headers = [
        { name = "Accept"; value = "*/*" },
        { name = "User-Agent"; value = "football_pickem_game_canister" },
        { name = "Ocp-Apim-Subscription-Key"; value = key },
    ];

    // 2.2.1 Transform context
    let transform_context : TransformContext = {
      function = transform;
      context = Blob.fromArray([]);
    };

    // 2.3 The HTTP request
    let http_request : HttpRequestArgs = {
        url = url;
        max_response_bytes = null; //optional for request
        headers = request_headers;
        body = null; //optional for request
        method = #get;
        transform = ?transform_context;
    };

    //3. ADD CYCLES TO PAY FOR HTTP REQUEST

    //The IC specification spec says, "Cycles to pay for the call must be explicitly transferred with the call"
    //IC management canister will make the HTTP request so it needs cycles
    //See: https://internetcomputer.org/docs/current/motoko/main/cycles
    
    //The way Cycles.add() works is that it adds those cycles to the next asynchronous call
    //"Function add(amount) indicates the additional amount of cycles to be transferred in the next remote call"
    //See: https://internetcomputer.org/docs/current/references/ic-interface-spec/#ic-http_request
    Cycles.add(230_949_972_000);
    
    //4. MAKE HTTPS REQUEST AND WAIT FOR RESPONSE
    //Since the cycles were added above, we can just call the IC management canister with HTTPS outcalls below
    let http_response : HttpResponsePayload = await ic.http_request(http_request);
    
    //5. DECODE THE RESPONSE

    //As per the type declarations in `src/Types.mo`, the BODY in the HTTP response 
    //comes back as [Nat8s] (e.g. [2, 5, 12, 11, 23]). Type signature:
    
    //public type HttpResponsePayload = {
    //     status : Nat;
    //     headers : [HttpHeader];
    //     body : [Nat8];
    // };

    //We need to decode that [Nat8] array that is the body into readable text. 
    //To do this, we:
    //  1. Convert the [Nat8] into a Blob
    //  2. Use Blob.decodeUtf8() method to convert the Blob to a ?Text optional 
    //  3. We use a switch to explicitly call out both cases of decoding the Blob into ?Text
    let response_body: Blob = Blob.fromArray(http_response.body);
    let decoded_text: Text = switch (Text.decodeUtf8(response_body)) {
        case (null) { "No value returned" };
        case (?y) { y };
    };

    //6. RETURN RESPONSE OF THE BODY
    //The API response will looks like this:

    // ("[[1682978460,5.714,5.718,5.714,5.714,243.5678]]")

    //Which can be formatted as this
    //  [
    //     [
    //         1682978460, <-- start/timestamp
    //         5.714, <-- low
    //         5.718, <-- high
    //         5.714, <-- open
    //         5.714, <-- close
    //         243.5678 <-- volume
    //     ],
    // ]

    // Update - football API data looks like this -- what to do with it?  Parse JSON?
    //     [
    //   {
    //     "GameID": 18684,
    //     "GlobalGameID": 18684,
    //     "ScoreID": 18684,
    //     "GameKey": "202410116",
    //     "Season": 2024,
    //     "SeasonType": 1,
    //     "Status": "Scheduled",
    //     "Canceled": false,
    //     "Date": "2024-09-05T20:20:00",
    //     "Day": "2024-09-05T00:00:00",
    //     "DateTime": "2024-09-05T20:20:00",
    //     "DateTimeUTC": "2024-09-06T00:20:00",
    //     "AwayTeam": "BAL",
    //     "HomeTeam": "KC",
    //     "GlobalAwayTeamID": 3,
    //     "GlobalHomeTeamID": 16,
    //     "AwayTeamID": 3,
    //     "HomeTeamID": 16,
    //     "StadiumID": 15,
    //     "Closed": null,
    //     "LastUpdated": null,
    //     "IsClosed": null,
    //     "Week": 1
    //   },
    //   {
    //     "GameID": 18683,
    //     "GlobalGameID": 18683,
    //     "ScoreID": 18683,
    //     "GameKey": "202410126",
    //     "Season": 2024,
    //     "SeasonType": 1,
    //     "Status": "Scheduled",
    //     "Canceled": false,
    //     "Date": "2024-09-06T20:15:00",
    //     "Day": "2024-09-06T00:00:00",
    //     "DateTime": "2024-09-06T20:15:00",
    //     "DateTimeUTC": "2024-09-07T00:15:00",
    //     "AwayTeam": "GB",
    //     "HomeTeam": "PHI",
    //     "GlobalAwayTeamID": 12,
    //     "GlobalHomeTeamID": 26,
    //     "AwayTeamID": 12,
    //     "HomeTeamID": 26,
    //     "StadiumID": 87,
    //     "Closed": null,
    //     "LastUpdated": null,
    //     "IsClosed": null,
    //     "Week": 1
    //   }
    // ]



    decoded_text
  };
};
