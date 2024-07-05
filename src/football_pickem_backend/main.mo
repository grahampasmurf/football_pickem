import Result "mo:base/Result";
import Time "mo:base/Time";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import TrieMap "mo:base/TrieMap";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Iter "mo:base/Iter";

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
    }
};
