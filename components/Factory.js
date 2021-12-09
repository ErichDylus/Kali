import React, { Component, useContext } from "react";
import AppContext from "../context/AppContext";
import Router, { useRouter } from "next/router";
import { Text, VStack, HStack, Box, Input, Button } from "@chakra-ui/react";
import FlexGradient from "./FlexGradient";
import { Formik, Form, Field, FieldArray } from "formik";
import * as Yup from "yup";
import FormikControl from "./form/FormikControl.js";
const abi = require("../abi/KaliDAOfactory.json");
import { factory_rinkeby } from "../utils/addresses";

export default function Factory(props) {
  const value = useContext(AppContext);
  const { web3, account, chainId, loading } = value.state;
  const factory = new web3.eth.Contract(abi, factory_rinkeby);

  const handleFactorySubmit = async (values) => {
    console.log("form:", values);
    /*      value.setLoading(true);

      const govSettings = "0,60,0,0,0,0,0,0,0,0,0,0";
      const extensions = new Array(0);
      const extensionsData = new Array(0);

      const {
        name,
        symbol,
        docs,
        voters,
        shares,
        votingPeriod,
        votingPeriodUnit,
      } = values;

      // convert shares to wei
      let sharesArray = [];
      for (let i = 0; i < shares.split(",").length; i++) {
        sharesArray.push(web3.utils.toWei(shares.split(",")[i]));
      }

      // convert voting period to appropriate unit
      if (votingPeriodUnit == "minutes") {
        votingPeriod *= 60;
      } else if (votingPeriodUnit == "hours") {
        votingPeriod *= 60 * 60;
      } else if (votingPeriodUnit == "days") {
        votingPeriod *= 60 * 60 * 24;
      } else if (votingPeriodUnit == "weeks") {
        votingPeriod *= 60 * 60 * 24 * 7;
      }

      // convert docs to appropriate links
      if (docs == "COC") {
        docs =
          "https://github.com/lexDAO/LexCorpus/blob/master/contracts/legal/dao/membership/CodeOfConduct.md";
      } else if (docs == "UNA") {
        docs =
          "https://github.com/lexDAO/LexCorpus/blob/master/contracts/legal/dao/membership/TUNAA.md";
      } else if (docs == "LLC") {
        docs =
          "https://github.com/lexDAO/LexCorpus/blob/master/contracts/legal/dao/membership/operating/DelawareOperatingAgreement.md";
      }

      console.log("votingPeriod:", votingPeriod);

      let votersArray = voters.split(",");
      let _voters = "";

      for (let i = 0; i < votersArray.length; i++) {
        if (votersArray[i].includes(".eth")) {
          votersArray[i] = await web3.eth.ens
            .getAddress(votersArray[i])
            .catch(() => {
              alert("ENS not found");
            });
        }

        if (i == votersArray.length - 1) {
          _voters += votersArray[i];
        } else {
          _voters += votersArray[i] + ",";
        }

        voters = _voters;
      }

      try {
        let result = await factory.methods
          .deployKaliDAO(
            name,
            symbol,
            docs,
            true,
            extensions,
            extensionsData,
            voters.split(","),
            sharesArray,
            votingPeriod,
            govSettings.split(",")
          )
          .send({ from: account });

        let dao = result["events"]["DAOdeployed"]["returnValues"]["kaliDAO"];

        Router.push({
          pathname: "/daos/[dao]",
          query: { dao: dao },
        });
      } catch (e) {
        alert(e);
        console.log(e);
      }

      value.setLoading(false)
*/
  };

  const initialForm = {
    name: "",
    symbol: "",
    docs: "",
    founders: [{ voter: "", share: "" }],
    votingPeriodUnit: "",
    votingPeriod: 1,
  };

  const validationSchema = Yup.object({
    name: Yup.string().required("Required"),
    symbol: Yup.string().required("Required"),
    founders: Yup.array(
      Yup.object({
        voter: Yup.string().required("Required"),
        share: Yup.string().required("Required"),
      })
    ),
    docs: Yup.string().required("Required"),
    votingPeriodUnit: Yup.string().required("Required"),
    votingPeriod: Yup.number().required("Required"),
  });

  const optionsDocs = [
    { key: "Select Document", value: "" },
    { key: "Code of Conduct", value: "COC" },
    { key: "UNA", value: "UNA" },
    { key: "LLC", value: "LLC" },
  ];

  const optionsVotingPeriod = [
    { key: "Select Voting Period", value: "" },
    { key: "Minutes", value: "minutes" },
    { key: "Hours", value: "hours" },
    { key: "Days", value: "days" },
  ];

  return (
    <FlexGradient>
      <Formik
        initialValues={initialForm}
        validationSchema={validationSchema}
        onSubmit={handleFactorySubmit}
      >
        {(values, errors) => (
          <Form>
            <FormikControl
              control="input"
              type="text"
              label="Name"
              name="name"
              placeholder="KaliDAO"
            />
            <FormikControl
              control="input"
              type="text"
              label="Symbol"
              name="symbol"
              placeholder="KALI"
            />
            <FormikControl
              control="select"
              label="Document"
              name="docs"
              options={optionsDocs}
            />
            <FieldArray name="founders"
              render={({ push, remove }) => (
                <>
                  {values.founders > 0 && 
                    values.founders.map((_, index) => (
                      <>
                        <FormikControl
                          control="input"
                          type="text"
                          label="Founder"
                          name={`founders.${index}.voter`}
                          placeholder="Enter ETH address or ENS"
                        />
                        <FormikControl
                          control="input"
                          type="text"
                          label="Share"
                          name={`founders.${index}.share`}
                          placeholder="1"
                        />
                        <Button onClick={() => remove(index)}>Delete</Button>
                      </>
                    ))}
                  
                    <Button onClick={() => push({ voter: "", share: "" })}>
                      Add Founder
                    </Button>
        
                </>
              )}
            />
            <FormikControl
              control="number-input"
              label="Voting Period"
              name="votingPeriod"
              defaultValue={3}
              min={1}
            />
            <FormikControl
              control="select"
              name="votingPeriodUnit"
              label="Voting Period Unit"
              options={optionsVotingPeriod}
            />
            <br />
            <Button type="submit" isFullWidth>
              Summon
            </Button>
            <pre>{JSON.stringify({ values, errors }, null, 4)}</pre>
          </Form>
        )}
      </Formik>
    </FlexGradient>
  );
}
