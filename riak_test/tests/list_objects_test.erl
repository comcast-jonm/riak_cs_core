-module(list_objects_test).

%% @doc Integration test for list the contents of a bucket

-export([confirm/0]).
-include_lib("eunit/include/eunit.hrl").

-define(TEST_BUCKET, "riak_test_bucket").

confirm() ->
    {RiakNodes, _CSNodes, _Stanchion} = rtcs:setup(4),

    FirstNode = hd(RiakNodes),

    {AccessKeyId, SecretAccessKey} = rtcs:create_user(FirstNode, 1),

    %% User config
    UserConfig = rtcs:config(AccessKeyId, SecretAccessKey, rtcs:cs_port(FirstNode)),

    lager:info("User is valid on the cluster, and has no buckets"),
    ?assertEqual([{buckets, []}], erlcloud_s3:list_buckets(UserConfig)),

    ?assertError({aws_error, {http_error, 404, _, _}}, erlcloud_s3:list_objects(?TEST_BUCKET, UserConfig)),

    lager:info("creating bucket ~p", [?TEST_BUCKET]),
    ?assertEqual(ok, erlcloud_s3:create_bucket(?TEST_BUCKET, UserConfig)),

    ?assertMatch([{buckets, [[{name, ?TEST_BUCKET}, _]]}],
        erlcloud_s3:list_buckets(UserConfig)),

    %% Put 10 objects in the bucket
    Count1 = 10,
    load_objects(?TEST_BUCKET, Count1, UserConfig),

    %% Successively list the buckets, verify the output, and delete an
    %% object from the bucket until the bucket is empty again.
    delete_and_verify_objects(?TEST_BUCKET, Count1, UserConfig),

    %% Put 100 objects in the bucket
    Count2 = 100,
    load_objects(?TEST_BUCKET, Count2, UserConfig),

    %% Successively list the buckets, verify the output, and delete an
    %% object from the bucket until the bucket is empty again.
    delete_and_verify_objects(?TEST_BUCKET, Count2, UserConfig),

    %% Put 30 objects in the bucket
    Count3 = 30,
    load_objects(?TEST_BUCKET, Count3, UserConfig),

    %% Use `max-keys' to restrict object list to 20 results
    Options1 = [{max_keys, 20}],
    ObjList1 = erlcloud_s3:list_objects(?TEST_BUCKET, Options1, UserConfig),
    Marker1 = proplists:get_value(marker, ObjList1),
    verify_object_list(ObjList1, 20),

    %% Use `marker' to request remainder of results
    Options2 = [{marker, Marker1}],
    verify_object_list(erlcloud_s3:list_objects(?TEST_BUCKET, Options2, UserConfig), 10),

    %% Put 2 sets of 4 objects with keys that have a common subdirectory
    load_objects(?TEST_BUCKET, 4, "subdir/prefix1/", UserConfig),
    load_objects(?TEST_BUCKET, 4, "subdir/prefix2/", UserConfig),

    %% Use `max-keys', `prefix' and `delimiter' to get first 30
    %% results back and verify results are truncated and 2 common
    %% prefixes are returned.
    %% Unable to currently verify the `CommonPrefixes' for this is
    %% fact that ercloud does not support parsing the those response
    %% elements.
    Options3 = [{max_keys, 30}, {prefix, "subdir"}, {delimiter, "/"}],
    ObjList2 = erlcloud_s3:list_objects(?TEST_BUCKET, Options3, UserConfig),
    Marker2 = proplists:get_value(marker, ObjList2),
    verify_object_list(ObjList1, 28),

    %% Request remainder of results
    Options3 = [{marker, Marker2}],
    verify_object_list(erlcloud_s3:list_objects(?TEST_BUCKET, Options3, UserConfig), 2),

    lager:info("deleting bucket ~p", [?TEST_BUCKET]),
    ?assertEqual(ok, erlcloud_s3:delete_bucket(?TEST_BUCKET, UserConfig)),

    ?assertError({aws_error, {http_error, 404, _, _}}, erlcloud_s3:list_objects(?TEST_BUCKET, UserConfig)),
    pass.

load_objects(Bucket, Count, Config) ->
    load_objects(Bucket, Count, [], Config).

load_objects(Bucket, Count, KeyPrefix, Config) ->
    [erlcloud_s3:put_object(Bucket,
                            KeyPrefix ++ integer_to_list(X),
                            crypto:rand_bytes(1000),
                            Config) || X <- lists:seq(1,Count)].

verify_object_list(ObjList, ExpectedCount) ->
    ?assertEqual(lists:sort([integer_to_list(X) || X <- lists:seq(1, ExpectedCount)]),
                 [proplists:get_value(key, O) ||
                     O <- proplists:get_value(contents, ObjList)]).

delete_and_verify_objects(Bucket, 0, Config) ->
    verify_object_list(erlcloud_s3:list_objects(Bucket, Config), 0),
    ok;
delete_and_verify_objects(Bucket, Count, Config) ->
    verify_object_list(erlcloud_s3:list_objects(Bucket, Config), Count),
    erlcloud_s3:delete_object(Bucket, integer_to_list(Count), Config),
    delete_and_verify_objects(Bucket, Count-1, Config).
